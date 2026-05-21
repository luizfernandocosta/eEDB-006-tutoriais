#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
SRC_DIR="${SCRIPT_DIR}/src"
DATA_DIR="${SCRIPT_DIR}/data"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="${ACCOUNT_ID}-emr-lab-wordcount"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

compile_java_local() {
    if ! command -v javac &>/dev/null; then
        return 1
    fi

    info "Compilando codigo Java localmente..."
    mkdir -p "${BUILD_DIR}"

    local hadoop_client_jar="${BUILD_DIR}/.deps/hadoop-client-runtime-3.3.6.jar"
    local hadoop_api_jar="${BUILD_DIR}/.deps/hadoop-client-3.3.6.jar"

    if [ ! -f "${hadoop_client_jar}" ]; then
        info "Baixando Hadoop client JARs para compilacao..."
        mkdir -p "${BUILD_DIR}/.deps"
        curl -sL "https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-client-runtime/3.3.6/hadoop-client-runtime-3.3.6.jar" \
            -o "${hadoop_client_jar}"
        curl -sL "https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-client/3.3.6/hadoop-client-3.3.6.jar" \
            -o "${hadoop_api_jar}"
    fi

    javac -classpath "${hadoop_api_jar}:${hadoop_client_jar}" \
        -d "${BUILD_DIR}" \
        "${SRC_DIR}"/*.java

    cd "${BUILD_DIR}" && jar cf wordcount.jar *.class && cd -
    info "JAR criado localmente: ${BUILD_DIR}/wordcount.jar"
    return 0
}

upload_to_s3() {
    info "Criando bucket S3 (se nao existir): ${BUCKET_NAME}"
    aws s3 mb "s3://${BUCKET_NAME}" 2>/dev/null || info "Bucket ja existe."

    if [ -f "${BUILD_DIR}/wordcount.jar" ] && [ "$(head -c 20 "${BUILD_DIR}/wordcount.jar" 2>/dev/null)" != "pending_compile" ]; then
        info "Upload do JAR compilado localmente..."
        aws s3 cp "${BUILD_DIR}/wordcount.jar" "s3://${BUCKET_NAME}/jars/wordcount.jar"
    else
        info "JAR nao compilado localmente. Upload dos fontes Java para compilacao no EMR..."
        aws s3 sync "${SRC_DIR}/" "s3://${BUCKET_NAME}/src/"
        info "O JAR sera compilado dentro do cluster EMR (step automatico)."
    fi

    info "Upload dos dados para s3://${BUCKET_NAME}/input/"
    aws s3 sync "${DATA_DIR}/" "s3://${BUCKET_NAME}/input/"

    info "Upload concluido!"
    echo ""
    echo "  Input:  s3://${BUCKET_NAME}/input/"
    echo "  JAR:    s3://${BUCKET_NAME}/jars/wordcount.jar (se compilado localmente)"
    echo "  Fontes: s3://${BUCKET_NAME}/src/ (se compilacao sera no EMR)"
    echo ""
}

main() {
    echo "========================================"
    echo "  Build + Upload para S3"
    echo "========================================"
    echo ""

    if ! command -v aws &>/dev/null; then
        error "AWS CLI nao encontrado. Execute o install.sh primeiro."
    fi

    mkdir -p "${BUILD_DIR}"

    if ! compile_java_local; then
        warn "Java JDK (javac) nao encontrado localmente."
        warn "Os fontes serao enviados ao S3 e compilados no cluster EMR."
        warn "Para compilacao local, instale Java JDK:"
        warn "  macOS:  brew install openjdk@11"
        warn "  Linux:  sudo apt install openjdk-11-jdk"
        warn "  Ou rode: ../install_aws_pre_req/install.sh"
        echo "pending_compile" > "${BUILD_DIR}/wordcount.jar"
    fi

    upload_to_s3

    echo "========================================"
    echo -e "  ${GREEN}Build + Upload concluidos!${NC}"
    echo "========================================"
}

main "$@"
