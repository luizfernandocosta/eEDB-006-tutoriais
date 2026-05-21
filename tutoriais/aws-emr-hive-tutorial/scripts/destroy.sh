#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="${ACCOUNT_ID}-emr-lab-hive"

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

        if [ "$state" = "TERMINATED" ] || [ "$state" = "TERMINATED_WITH_ERRORS" ]; then
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
    echo "  Descomissionamento EMR + Hive"
    echo "========================================"
    echo ""

    local mode=${1:-"all"}

    case "$mode" in
        all)
            info "Destruindo recursos via Terraform..."
            cd "${SCRIPT_DIR}/terraform" && terraform destroy -auto-approve 2>/dev/null || {
                warn "Terraform destroy falhou ou nao ha estado. Tentando CLI manual..."

                local clusters
                clusters=$(aws emr list-clusters --cluster-states STARTING BOOTSTRAPPING RUNNING WAITING --query 'Clusters[].Id' --output text 2>/dev/null)
                for id in $clusters; do
                    terminate_cluster "$id"
                done

                empty_s3_bucket
            }

            rm -rf "${SCRIPT_DIR}/.terraform" "${SCRIPT_DIR}/terraform/.terraform" "${SCRIPT_DIR}/terraform/terraform.tfstate"* 2>/dev/null || true

            echo ""
            echo "========================================"
            echo -e "  ${GREEN}Descomissionamento concluido!${NC}"
            echo "========================================"
            ;;
        cluster)
            local clusters
            clusters=$(aws emr list-clusters --cluster-states STARTING BOOTSTRAPPING RUNNING WAITING --query 'Clusters[].Id' --output text 2>/dev/null)
            if [ -n "$clusters" ]; then
                for id in $clusters; do
                    terminate_cluster "$id"
                done
            else
                warn "Nenhum cluster ativo encontrado."
            fi
            ;;
        s3)
            empty_s3_bucket
            ;;
        terraform)
            info "Destruindo via Terraform..."
            cd "${SCRIPT_DIR}/terraform" && terraform destroy -auto-approve
            ;;
        *)
            echo "Uso: $0 {all|cluster|s3|terraform}"
            echo ""
            echo "  all       - Destroi tudo (Terraform > CLI > S3)"
            echo "  cluster   - Encerra clusters EMR ativos"
            echo "  s3        - Esvazia e remove bucket S3"
            echo "  terraform - terraform destroy direto"
            ;;
    esac
}

main "$@"
