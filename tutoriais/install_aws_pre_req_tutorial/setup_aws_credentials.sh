#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRED_DIR="${SCRIPT_DIR}/../aws_credenciais"

AWS_DIR="${HOME}/.aws"
SSH_DIR="${HOME}/.ssh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

setup_aws_dir() {
    info "Criando diretorio ${AWS_DIR}..."
    mkdir -p "${AWS_DIR}"
}

copy_credentials() {
    if [[ ! -f "${CRED_DIR}/credentials" ]]; then
        error "Arquivo nao encontrado: ${CRED_DIR}/credentials"
        exit 1
    fi

    if [[ ! -f "${CRED_DIR}/config" ]]; then
        error "Arquivo nao encontrado: ${CRED_DIR}/config"
        exit 1
    fi

    info "Copiando credentials para ${AWS_DIR}/credentials..."
    cp -f "${CRED_DIR}/credentials" "${AWS_DIR}/credentials"
    chmod 600 "${AWS_DIR}/credentials"

    info "Copiando config para ${AWS_DIR}/config..."
    cp -f "${CRED_DIR}/config" "${AWS_DIR}/config"
    chmod 644 "${AWS_DIR}/config"
}

copy_ssh_key() {
    local pem_file="${CRED_DIR}/labsuser.pem"

    if [[ -f "${pem_file}" ]]; then
        info "Copiando chave SSH para ${SSH_DIR}/labsuser.pem..."
        mkdir -p "${SSH_DIR}"
        cp -f "${pem_file}" "${SSH_DIR}/labsuser.pem"
        chmod 600 "${SSH_DIR}/labsuser.pem"
    else
        warn "Chave SSH nao encontrada: ${pem_file} (pulando)"
    fi
}

validate_aws_cli() {
    if ! command -v aws &>/dev/null; then
        error "AWS CLI nao encontrado. Execute install.sh primeiro."
        exit 1
    fi
    info "AWS CLI encontrado: $(aws --version 2>&1)"
}

validate_connection() {
    echo ""
    echo "========================================"
    echo "    Validando Conexao com AWS"
    echo "========================================"

    info "Executando: aws sts get-caller-identity"
    if aws sts get-caller-identity 2>&1; then
        echo ""
        echo -e "${GREEN}========================================"
        echo "  CONEXAO AWS VALIDADA COM SUCESSO!"
        echo "========================================${NC}"
        echo ""
        echo "Voce esta autenticado na AWS."
        echo "Regiao configurada: $(aws configure get region 2>/dev/null || echo 'us-east-1')"
        echo ""
        echo "Proximo passo: inicializar o Terraform"
        echo "  terraform init"
    else
        echo ""
        echo -e "${RED}========================================"
        echo "  FALHA NA CONEXAO AWS"
        echo "========================================${NC}"
        echo ""
        echo "Possiveis causas:"
        echo "  1. Credenciais expiradas (session token temporario)"
        echo "  2. Arquivos de credencial incorretos"
        echo "  3. Sem conexao com a internet"
        echo ""
        echo "Solucao:"
        echo "  - Atualize os arquivos em tutoriais/aws_credenciais/"
        echo "  - Re-execute: ./setup_aws_credentials.sh"
        exit 1
    fi
}

main() {
    echo "========================================"
    echo "  Configurador de Credenciais AWS"
    echo "========================================"
    echo ""
    echo "Origem:  ${CRED_DIR}"
    echo "Destino: ${AWS_DIR}"
    echo ""

    validate_aws_cli
    setup_aws_dir
    copy_credentials
    copy_ssh_key
    validate_connection
}

main "$@"
