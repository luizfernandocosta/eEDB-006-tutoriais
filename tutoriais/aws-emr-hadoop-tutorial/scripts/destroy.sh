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

terminate_cluster() {
    local cluster_id=$1

    info "Encerrando cluster ${cluster_id}..."
    aws emr terminate-clusters --cluster-ids "$cluster_id"

    info "Aguardando termino do cluster..."
    local elapsed=0
    while [ $elapsed -lt 300 ]; do
        local state
        state=$(aws emr describe-cluster --cluster-id "$cluster_id" --query 'Cluster.Status.State' --output text 2>/dev/null || echo "UNKNOWN")

        if [ "$state" = "TERMINATED" ]; then
            info "Cluster terminado com sucesso!"
            return 0
        fi

        echo -ne "\r  Estado: ${state} (${elapsed}s)  "
        sleep 15
        elapsed=$((elapsed + 15))
    done
    warn "Timeout aguardando termino. Verifique manualmente."
}

empty_s3_bucket() {
    info "Esvaziando bucket S3: ${BUCKET_NAME}..."
    aws s3 rm "s3://${BUCKET_NAME}" --recursive 2>/dev/null || warn "Bucket nao encontrado ou ja vazio."

    info "Removendo bucket..."
    aws s3 rb "s3://${BUCKET_NAME}" 2>/dev/null || warn "Bucket nao pode ser removido (talvez nao esteja vazio)."
}

main() {
    echo "========================================"
    echo "  Descomissionamento EMR"
    echo "========================================"
    echo ""

    local mode=${1:-"all"}

    case "$mode" in
        all)
            if [ -f "${SCRIPT_DIR}/.cluster_id" ]; then
                local cluster_id
                cluster_id=$(cat "${SCRIPT_DIR}/.cluster_id")
                info "Cluster ID encontrado: ${cluster_id}"

                local state
                state=$(aws emr describe-cluster --cluster-id "$cluster_id" --query 'Cluster.Status.State' --output text 2>/dev/null || echo "NOT_FOUND")

                if [ "$state" != "TERMINATED" ] && [ "$state" != "NOT_FOUND" ]; then
                    terminate_cluster "$cluster_id"
                else
                    info "Cluster ja terminado ou nao encontrado."
                fi

                rm -f "${SCRIPT_DIR}/.cluster_id"
            else
                warn "Nenhum arquivo .cluster_id encontrado."
                info "Listando clusters ativos..."
                local clusters
                clusters=$(aws emr list-clusters --cluster-states STARTING BOOTSTRAPPING RUNNING WAITING --query 'Clusters[].{Id:Id,Name:Name,State:Status.State}' --output table 2>/dev/null)

                if [ "$clusters" = "" ] || [ "$clusters" = "None" ]; then
                    info "Nenhum cluster ativo encontrado."
                else
                    echo "$clusters"
                    echo ""
                    read -p "Deseja encerrar todos os clusters? (y/N) " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        for id in $(aws emr list-clusters --cluster-states STARTING BOOTSTRAPPING RUNNING WAITING --query 'Clusters[].Id' --output text 2>/dev/null); do
                            terminate_cluster "$id"
                        done
                    fi
                fi
            fi

            empty_s3_bucket

            if [ -d "${SCRIPT_DIR}/terraform" ]; then
                info "Destruindo recursos Terraform (se aplicavel)..."
                cd "${SCRIPT_DIR}/terraform" && terraform destroy -auto-approve 2>/dev/null || warn "Nenhum estado Terraform encontrado."
            fi

            rm -rf "${SCRIPT_DIR}/build" "${SCRIPT_DIR}/results" "${SCRIPT_DIR}/.terraform" "${SCRIPT_DIR}/terraform/.terraform" "${SCRIPT_DIR}/terraform/terraform.tfstate"* 2>/dev/null || true

            echo ""
            echo "========================================"
            echo -e "  ${GREEN}Descomissionamento concluido!${NC}"
            echo "========================================"
            ;;
        cluster)
            if [ -f "${SCRIPT_DIR}/.cluster_id" ]; then
                terminate_cluster "$(cat "${SCRIPT_DIR}/.cluster_id")"
                rm -f "${SCRIPT_DIR}/.cluster_id"
            else
                error "Nenhum arquivo .cluster_id encontrado."
            fi
            ;;
        s3)
            empty_s3_bucket
            ;;
        *)
            echo "Uso: $0 {all|cluster|s3}"
            echo ""
            echo "  all     - Encerra cluster, esvazia S3, remove Terraform (padrao)"
            echo "  cluster - Encerra apenas o cluster EMR"
            echo "  s3      - Esvazia e remove apenas o bucket S3"
            ;;
    esac
}

main "$@"
