#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="${ACCOUNT_ID}-emr-lab-wordcount"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

need_compile_on_emr() {
    local jar_s3
    jar_s3=$(aws s3 ls "s3://${BUCKET_NAME}/jars/wordcount.jar" --query 'Contents[].Size' --output text 2>/dev/null || echo "0")
    if [ "$jar_s3" = "0" ] || [ "$jar_s3" = "" ]; then
        return 0
    fi
    return 1
}

wait_for_cluster() {
    local cluster_id=$1
    local desired_state=${2:-"WAITING"}
    local max_wait=${3:-900}
    local elapsed=0

    info "Aguardando cluster ${cluster_id} atingir estado ${desired_state} (max ${max_wait}s)..."

    while [ $elapsed -lt $max_wait ]; do
        local state
        state=$(aws emr describe-cluster --cluster-id "$cluster_id" --query 'Cluster.Status.State' --output text 2>/dev/null || echo "UNKNOWN")

        if [ "$state" = "$desired_state" ]; then
            echo ""
            info "Cluster no estado ${desired_state}!"
            return 0
        fi

        if [ "$state" = "TERMINATED" ] || [ "$state" = "TERMINATED_WITH_ERRORS" ]; then
            echo ""
            error "Cluster terminou inesperadamente: ${state}"
        fi

        echo -ne "\r  Estado: ${state} (${elapsed}s / ${max_wait}s)  "
        sleep 30
        elapsed=$((elapsed + 30))
    done

    echo ""
    error "Timeout aguardando cluster atingir ${desired_state}"
}

wait_for_step() {
    local cluster_id=$1
    local step_id=$2
    local max_wait=${3:-600}
    local elapsed=0

    info "Aguardando step ${step_id}..."

    while [ $elapsed -lt $max_wait ]; do
        local state
        state=$(aws emr describe-step --cluster-id "$cluster_id" --step-id "$step_id" --query 'Step.Status.State' --output text 2>/dev/null || echo "UNKNOWN")

        if [ "$state" = "COMPLETED" ]; then
            echo ""
            info "Step concluido!"
            return 0
        fi

        if [ "$state" = "FAILED" ] || [ "$state" = "CANCELLED" ]; then
            echo ""
            error "Step falhou: ${state}"
        fi

        echo -ne "\r  Step: ${state} (${elapsed}s / ${max_wait}s)  "
        sleep 15
        elapsed=$((elapsed + 15))
    done

    echo ""
    error "Timeout aguardando step"
}

create_cluster() {
    info "Criando cluster EMR..."

    local cluster_id
    cluster_id=$(aws emr create-cluster \
        --name "wordcount-emr-cluster" \
        --release-label "emr-6.15.0" \
        --applications Name=Hadoop Name=MapReduce \
        --service-role "EMR_DefaultRole" \
        --job-flow-role "EMR_EC2_DefaultRole" \
        --ec2-attributes KeyName=vockey,InstanceProfile=EMR_EC2_DefaultRole \
        --instance-groups \
            '[{"InstanceGroupType":"MASTER","InstanceCount":1,"InstanceType":"m4.large","Name":"Master"},
              {"InstanceGroupType":"CORE","InstanceCount":1,"InstanceType":"m4.large","Name":"Core"}]' \
        --no-auto-terminate \
        --query 'ClusterId' \
        --output text 2>&1)

    if echo "$cluster_id" | grep -qE "(An error|error)"; then
        error "Falha ao criar cluster: ${cluster_id}"
    fi

    info "Cluster criado: ${cluster_id}"
    echo "$cluster_id"
}

submit_compile_step() {
    local cluster_id=$1

    info "[Step 1/4] Compilando Java no cluster EMR..."
    local step_id
    step_id=$(aws emr add-steps --cluster-id "$cluster_id" --steps \
        '[{"Name":"Compile-WordCount-JAR","ActionOnFailure":"TERMINATE_CLUSTER","HadoopJarStep":{"Jar":"command-runner.jar","Args":["bash","-c","set -e; HADOOP_CLASSPATH=$($HADOOP_HOME/bin/hadoop classpath); mkdir -p /home/hadoop/wc-build; aws s3 cp s3://'${BUCKET_NAME}'/src/ /home/hadoop/wc-build/ --recursive; javac -classpath \"$HADOOP_CLASSPATH\" -d /home/hadoop/wc-build /home/hadoop/wc-build/*.java; cd /home/hadoop/wc-build && jar cf /home/hadoop/wc-build/wordcount.jar *.class; aws s3 cp /home/hadoop/wc-build/wordcount.jar s3://'${BUCKET_NAME}'/jars/wordcount.jar; echo Compile done"]}}]' \
        --query 'StepIds[0]' --output text)

    info "Compile step ID: ${step_id}"
    wait_for_step "$cluster_id" "$step_id" 300
}

submit_wordcount_steps() {
    local cluster_id=$1

    info "[Step 2/4] Copiando dados do S3 para HDFS..."
    local step1
    step1=$(aws emr add-steps --cluster-id "$cluster_id" --steps \
        '[{"Name":"Copy-S3-to-HDFS","ActionOnFailure":"CONTINUE","HadoopJarStep":{"Jar":"command-runner.jar","Args":["s3-dist-cp","--src","s3://'${BUCKET_NAME}'/input/","--dest","hdfs:///input/"]}}]' \
        --query 'StepIds[0]' --output text)
    info "Step 2 ID: ${step1}"
    wait_for_step "$cluster_id" "$step1" 300

    info "[Step 3/4] Executando WordCount MapReduce..."
    local step2
    step2=$(aws emr add-steps --cluster-id "$cluster_id" --steps \
        '[{"Name":"Run-WordCount","ActionOnFailure":"CONTINUE","HadoopJarStep":{"Jar":"s3://'${BUCKET_NAME}'/jars/wordcount.jar","Args":["hdfs:///input/","hdfs:///output/wordcount/"]}}]' \
        --query 'StepIds[0]' --output text)
    info "Step 3 ID: ${step2}"
    wait_for_step "$cluster_id" "$step2" 600

    info "[Step 4/4] Copiando resultados do HDFS para S3..."
    local step3
    step3=$(aws emr add-steps --cluster-id "$cluster_id" --steps \
        '[{"Name":"Copy-HDFS-to-S3","ActionOnFailure":"CONTINUE","HadoopJarStep":{"Jar":"command-runner.jar","Args":["s3-dist-cp","--src","hdfs:///output/wordcount/","--dest","s3://'${BUCKET_NAME}'/output/"]}}]' \
        --query 'StepIds[0]' --output text)
    info "Step 4 ID: ${step3}"
    wait_for_step "$cluster_id" "$step3" 300

    info "Todos os steps concluidos!"
}

show_results() {
    info "Baixando e exibindo resultados..."
    echo ""
    echo "========================================"
    echo "  Arquivos de saida no S3:"
    echo "========================================"
    aws s3 ls "s3://${BUCKET_NAME}/output/" 2>/dev/null || warn "Nenhum resultado encontrado."

    echo ""
    echo "========================================"
    echo "  Top 20 palavras mais frequentes:"
    echo "========================================"
    mkdir -p "${SCRIPT_DIR}/results"
    aws s3 sync "s3://${BUCKET_NAME}/output/" "${SCRIPT_DIR}/results/" 2>/dev/null || true

    if [ -f "${SCRIPT_DIR}/results/part-r-00000" ]; then
        sort -t$'\t' -k2 -nr "${SCRIPT_DIR}/results/part-r-00000" | head -20
        echo ""
        local total
        total=$(wc -l < "${SCRIPT_DIR}/results/part-r-00000")
        info "Total de palavras unicas: ${total}"
        info "Resultados salvos em: ${SCRIPT_DIR}/results/"
    else
        warn "Resultado nao disponivel localmente. Baixe manualmente:"
        warn "  aws s3 sync s3://${BUCKET_NAME}/output/ ./results/"
    fi
    echo ""
}

main() {
    echo "========================================"
    echo "  EMR WordCount - Modo Automatico"
    echo "========================================"
    echo ""

    if ! command -v aws &>/dev/null; then
        error "AWS CLI nao encontrado."
    fi

    local mode=${1:-"full"}

    case "$mode" in
        full)
            local cluster_id
            cluster_id=$(create_cluster)
            echo "${cluster_id}" > "${SCRIPT_DIR}/.cluster_id"
            info "Cluster ID salvo em .cluster_id"
            echo ""

            wait_for_cluster "$cluster_id" "WAITING" 900

            if need_compile_on_emr; then
                info "JAR nao encontrado no S3. Compilando no cluster EMR..."
                submit_compile_step "$cluster_id"
            else
                info "JAR ja existe no S3. Pulando compilacao."
            fi

            submit_wordcount_steps "$cluster_id"
            show_results

            echo "========================================"
            echo -e "  ${GREEN}Execucao concluida!${NC}"
            echo "========================================"
            echo ""
            echo "  Cluster ID: ${cluster_id}"
            echo "  S3 output:  s3://${BUCKET_NAME}/output/"
            echo "  Local:      ${SCRIPT_DIR}/results/"
            echo ""
            echo "  Para SSH:     ./scripts/run-wordcount-emr.sh ssh"
            echo "  Para encerrar: ./scripts/destroy.sh"
            echo "========================================"
            ;;
        results)
            show_results
            ;;
        ssh)
            if [ ! -f "${SCRIPT_DIR}/.cluster_id" ]; then
                error "Nenhum cluster encontrado. Rode './scripts/run-wordcount-emr.sh full' primeiro."
            fi
            local cluster_id
            cluster_id=$(cat "${SCRIPT_DIR}/.cluster_id")
            local master_dns
            master_dns=$(aws emr describe-cluster --cluster-id "$cluster_id" --query 'Cluster.MasterPublicDnsName' --output text)
            info "Conectando ao master: ${master_dns}"
            ssh -i ~/.ssh/labsuser.pem -o StrictHostKeyChecking=no hadoop@"${master_dns}"
            ;;
        status)
            if [ ! -f "${SCRIPT_DIR}/.cluster_id" ]; then
                error "Nenhum cluster encontrado."
            fi
            local cluster_id
            cluster_id=$(cat "${SCRIPT_DIR}/.cluster_id")
            aws emr describe-cluster --cluster-id "$cluster_id" \
                --query 'Cluster.{Name:Name,State:Status.State,Master:MasterPublicDnsName}' --output table
            echo ""
            aws emr list-steps --cluster-id "$cluster_id" \
                --query 'Steps[].{Name:Name,State:Status.State,Start:Status.Timeline.StartDateTime}' --output table
            ;;
        *)
            echo "Uso: $0 {full|results|ssh|status}"
            echo ""
            echo "  full    - Cria cluster, compila (se necessario), roda WordCount (padrao)"
            echo "  results - Baixa e mostra resultados"
            echo "  ssh     - SSH ao master node"
            echo "  status  - Mostra estado do cluster e steps"
            ;;
    esac
}

main "$@"
