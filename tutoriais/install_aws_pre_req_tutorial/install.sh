#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

detect_os() {
    local uname_out="$(uname -s)"
    case "${uname_out}" in
        Linux*)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                echo "wsl"
            else
                echo "linux"
            fi
            ;;
        Darwin*)
            echo "macos"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            echo "windows"
            ;;
        *)
            error "SO nao suportado: ${uname_out}"
            ;;
    esac
}

check_installed() {
    command -v "$1" &>/dev/null
}

install_awscli_macos() {
    if check_installed aws; then
        warn "AWS CLI ja instalado: $(aws --version 2>&1)"
        return 0
    fi

    info "Instalando AWS CLI v2 no macOS..."
    local tmpdir="$(mktemp -d)"
    curl -sL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "${tmpdir}/AWSCLIV2.pkg"
    sudo installer -pkg "${tmpdir}/AWSCLIV2.pkg" -target /
    rm -rf "${tmpdir}"
    info "AWS CLI instalado com sucesso."
}

install_awscli_linux() {
    if check_installed aws; then
        warn "AWS CLI ja instalado: $(aws --version 2>&1)"
        return 0
    fi

    info "Instalando AWS CLI v2 no Linux..."
    local tmpdir="$(mktemp -d)"
    local arch="$(uname -m)"
    local url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
    if [[ "$arch" == "aarch64" ]]; then
        url="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
    fi

    curl -sL "$url" -o "${tmpdir}/awscliv2.zip"
    cd "${tmpdir}" && unzip -q awscliv2.zip
    sudo ./aws/install -i /usr/local/aws-cli -b /usr/local/bin
    cd -
    rm -rf "${tmpdir}"
    info "AWS CLI instalado com sucesso."
}

install_terraform_macos() {
    if check_installed terraform; then
        warn "Terraform ja instalado: $(terraform version 2>&1 | head -1)"
        return 0
    fi

    if check_installed brew; then
        info "Instalando Terraform via Homebrew..."
        brew tap hashicorp/tap
        brew install hashicorp/tap/terraform
    else
        install_terraform_linux
    fi
    info "Terraform instalado com sucesso."
}

install_terraform_linux() {
    if check_installed terraform; then
        warn "Terraform ja instalado: $(terraform version 2>&1 | head -1)"
        return 0
    fi

    info "Instalando Terraform (ultima versao estavel)..."
    local tf_version
    tf_version=$(curl -sL https://releases.hashicorp.com/terraform/index.json | \
        grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [[ -z "$tf_version" ]]; then
        error "Nao foi possivel determinar a versao mais recente do Terraform."
    fi

    info "Baixando Terraform ${tf_version}..."
    local arch="$(uname -m)"
    local tf_os="linux"
    local tf_arch="amd64"

    if [[ "$(detect_os)" == "macos" ]]; then
        tf_os="darwin"
    fi
    if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
        tf_arch="arm64"
    fi

    local tmpdir="$(mktemp -d)"
    curl -sL "https://releases.hashicorp.com/terraform/${tf_version}/terraform_${tf_version}_${tf_os}_${tf_arch}.zip" \
        -o "${tmpdir}/terraform.zip"
    cd "${tmpdir}" && unzip -o terraform.zip
    sudo mv terraform /usr/local/bin/terraform
    cd -
    rm -rf "${tmpdir}"
    info "Terraform ${tf_version} instalado com sucesso."
}

install_java_macos() {
    if check_installed javac; then
        warn "Java ja instalado: $(javac -version 2>&1)"
        return 0
    fi

    if check_installed brew; then
        info "Instalando OpenJDK 11 via Homebrew..."
        brew install openjdk@11
        sudo ln -sfn "$(brew --prefix openjdk@11)/libexec/openjdk.jdk" /Library/Java/JavaVirtualMachines/openjdk-11.jdk
        export JAVA_HOME="$(brew --prefix openjdk@11)/libexec/openjdk.jdk/Contents/Home"
        info "Java instalado. Adicione ao ~/.zshrc:"
        info '  export JAVA_HOME="$(brew --prefix openjdk@11)/libexec/openjdk.jdk/Contents/Home"'
        info '  export PATH="$JAVA_HOME/bin:$PATH"'
    else
        warn "Homebrew nao encontrado. Instale manualmente: https://adoptium.net/"
    fi
}

install_java_linux() {
    if check_installed javac; then
        warn "Java ja instalado: $(javac -version 2>&1)"
        return 0
    fi

    info "Instalando OpenJDK 11..."
    if check_installed apt; then
        sudo apt update -qq
        sudo apt install -y openjdk-11-jdk
    elif check_installed yum; then
        sudo yum install -y java-11-openjdk-devel
    else
        warn "Gerenciador de pacotes nao reconhecido. Instale manualmente: https://adoptium.net/"
        return 0
    fi
    info "Java instalado com sucesso."
}

validate_installation() {
    echo ""
    echo "========================================"
    echo "       Validacao da Instalacao"
    echo "========================================"

    if check_installed aws; then
        info "AWS CLI: $(aws --version 2>&1)"
    else
        error "AWS CLI nao encontrado no PATH."
    fi

    if check_installed terraform; then
        info "Terraform: $(terraform version 2>&1 | head -1)"
    else
        error "Terraform nao encontrado no PATH."
    fi

    if check_installed javac; then
        info "Java JDK: $(javac -version 2>&1)"
    else
        warn "Java JDK nao encontrado. Instalacao opcional (compilacao no EMR tambem funciona)."
    fi

    echo "========================================"
    echo -e "${GREEN}Instalacao concluida com sucesso!${NC}"
    echo ""
    echo "Proximo passo: configure as credenciais AWS"
    echo "  ./setup_aws_credentials.sh"
    echo "========================================"
}

main() {
    echo "========================================"
    echo "  Instalador: AWS CLI v2 + Terraform + Java JDK"
    echo "========================================"

    local os
    os="$(detect_os)"
    info "SO detectado: ${os}"

    case "${os}" in
        macos)
            install_awscli_macos
            install_terraform_macos
            install_java_macos
            ;;
        linux|wsl)
            install_awscli_linux
            install_terraform_linux
            install_java_linux
            ;;
        windows)
            error "No Windows nativo, use WSL ou Git Bash. Instale manualmente via: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-windows.html"
            ;;
    esac

    validate_installation
}

main "$@"
