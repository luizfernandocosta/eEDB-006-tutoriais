# Tutorial: Instalacao do AWS CLI v2 + Terraform

## Visao Geral

Este tutorial instala o **AWS CLI v2** e o **Terraform** em macOS, Linux e Windows, e configura as credenciais AWS automaticamente a partir dos arquivos em `tutoriais/aws_credenciais/`.

---

## Prerequisitos

| SO | Requisito |
|---|---|
| macOS | Terminal (zsh/bash), `curl`, `unzip` |
| Linux | bash, `curl`, `unzip` |
| Windows | **PowerShell** (nativo) — ou WSL/Git Bash como alternativa |

---

## Estrutura de Arquivos

```
tutoriais/
  aws_credenciais/
    config            # Regiao AWS
    credentials       # Chaves de acesso (temporarias)
    labsuser.pem      # Chave SSH para EC2
  install_aws_pre_req/
    TUTORIAL.md       # Este arquivo
    install.sh        # Script de instalacao do AWS CLI + Terraform
    setup_aws_credentials.sh  # Script de configuracao de credenciais
```

---

## Passo 1 — Instalar AWS CLI e Terraform

### Opcao A: Script automatico (recomendado)

```bash
chmod +x ./tutoriais/install_aws_pre_req_tutorial/install.sh
./tutoriais/install_aws_pre_req_tutorial/install.sh
```

O script detecta o SO e instala automaticamente.

### Opcao B: Instalacao manual

#### macOS

```bash
# AWS CLI v2
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /
rm AWSCLIV2.pkg

# Terraform (via Homebrew)
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

#### Linux (Ubuntu/Debian)

```bash
# AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip

# Terraform
TERRAFORM_VERSION=$(curl -sL https://releases.hashicorp.com/terraform/index.json | \
  grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)
curl -Lo terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
unzip terraform.zip
sudo mv terraform /usr/local/bin/
rm terraform.zip
```

#### Linux (RHEL/CentOS/Fedora/Amazon Linux)

```bash
# AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip

# Terraform (mesmo processo)
sudo yum install -y unzip
TERRAFORM_VERSION=$(curl -sL https://releases.hashicorp.com/terraform/index.json | \
  grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)
curl -Lo terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
unzip terraform.zip
sudo mv terraform /usr/local/bin/
rm terraform.zip
```

#### Windows (Instalacao Nativa via PowerShell)

##### AWS CLI v2

1. Baixe o instalador MSI:
   - **64-bit**: https://awscli.amazonaws.com/AWSCLIV2.msi
2. Execute o arquivo `.msi` baixado e siga o assistente de instalacao
3. Ou via PowerShell (como Administrador):

```powershell
# Baixar e instalar AWS CLI v2
Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile "AWSCLIV2.msi"
Start-Process msiexec.exe -Wait -ArgumentList '/I AWSCLIV2.msi /quiet'
Remove-Item AWSCLIV2.msi

# Validar
aws --version
```

##### Terraform

1. Acesse https://developer.hashicorp.com/terraform/downloads
2. Baixe o arquivo `windows_amd64.zip`
3. Ou via PowerShell:

```powershell
# Descobrir ultima versao
$tfVersion = (Invoke-RestMethod -Uri "https://releases.hashicorp.com/terraform/index.json").versions.PSObject.Properties.Name | Where-Object { $_ -notmatch "-" } | Sort-Object { [version]$_ } -Descending | Select-Object -First 1

# Baixar e instalar
Invoke-WebRequest -Uri "https://releases.hashicorp.com/terraform/${tfVersion}/terraform_${tfVersion}_windows_amd64.zip" -OutFile "terraform.zip"
Expand-Archive -Path terraform.zip -DestinationPath "C:\terraform"
Remove-Item terraform.zip

# Adicionar ao PATH (usuario atual)
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\terraform", "User")

# Reabra o terminal e valide
terraform version
```

##### Configurar credenciais no Windows (PowerShell)

```powershell
# Criar diretorio AWS
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.aws"
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.ssh"

# Copiar credenciais (ajuste o caminho do projeto)
$projDir = "C:\caminho\para\Big Data\tutoriais\aws_credenciais"
Copy-Item "$projDir\credentials" "$env:USERPROFILE\.aws\credentials"
Copy-Item "$projDir\config" "$env:USERPROFILE\.aws\config"
Copy-Item "$projDir\labsuser.pem" "$env:USERPROFILE\.ssh\labsuser.pem"

# Validar conexao
aws sts get-caller-identity
```

> **Dica**: Para manter as credenciais atualizadas no Windows, basta re-executar os comandos `Copy-Item` acima sempre que os arquivos em `tutoriais/aws_credenciais/` forem atualizados.

---

#### Windows (Alternativa via WSL - Ubuntu)

Se preferir usar WSL, as instrucoes sao identicas a instalacao Linux Ubuntu:

```bash
# Dentro do WSL (Ubuntu)
# Rode o script install.sh ou siga as instrucoes Linux acima
chmod +x install.sh
./install.sh
```

Para configurar as credenciais no WSL:

```bash
chmod +x setup_aws_credentials.sh
./setup_aws_credentials.sh
```

> **Nota**: Ao usar WSL, as credenciais ficam em `~/.aws/` dentro do ambiente Linux do WSL, separado do Windows nativo. Se precisar usar o AWS CLI tanto no Windows quanto no WSL, configure em ambos.

---

## Passo 2 — Configurar Credenciais AWS (macOS/Linux/WSL)

```bash
chmod +x tutoriais/install_aws_pre_req/setup_aws_credentials.sh
./tutoriais/install_aws_pre_req/setup_aws_credentials.sh
```

Este script:
1. Cria `~/.aws/` se nao existir
2. Copia `config` e `credentials` de `tutoriais/aws_credenciais/` para `~/.aws/`
3. Copia `labsuser.pem` para `~/.ssh/` com permissao 600
4. Valida a conexao AWS executando `aws sts get-caller-identity`

### Atualizar credenciais (quando expirarem)

As credenciais deste lab sao **temporarias** (possuem session token). Quando expirarem:

1. Faca download dos novos arquivos `config` e `credentials`
2. Substitua em `tutoriais/aws_credenciais/`
3. Re-execute o script:

```bash
./tutoriais/install_aws_pre_req/setup_aws_credentials.sh
```

---

## Passo 3 — Validar Instalacao

```bash
# Verificar versoes
aws --version
terraform version

# Verificar identidade AWS
aws sts get-caller-identity

# Listar regioes disponiveis
aws ec2 describe-regions --query 'Regions[].RegionName' --output table
```

---

## Comandos Uteis

```bash
# Listar instancias EC2
aws ec2 describe-instances --query 'Reservations[].Instances[].{ID:InstanceId,State:State.Name,Type:InstanceType}'

# Listar buckets S3
aws s3 ls

# Inicializar projeto Terraform
terraform init

# Ver plano de execucao
terraform plan

# Aplicar infraestrutura
terraform apply
```

---

## Troubleshooting

| Problema | Solucao |
|---|---|
| `aws: command not found` | Reinicie o terminal ou rode `source ~/.zshrc` / `source ~/.bashrc` |
| `terraform: command not found` | Verifique se `/usr/local/bin` esta no `$PATH` |
| `The security token included in the request is expired` | Credenciais expiradas — atualize os arquivos e re-rode `setup_aws_credentials.sh` |
| `Unable to locate credentials` | Rode `setup_aws_credentials.sh` ou verifique `~/.aws/credentials` |
| Permissao denied no `.pem` | `chmod 600 ~/.ssh/labsuser.pem` |
| Windows: `aws` nao reconhecido | Reabra o PowerShell/CMD; verifique se `C:\Program Files\Amazon\AWSCLIV2` esta no PATH |
| Windows: `terraform` nao reconhecido | Verifique se `C:\terraform` foi adicionado ao PATH; reabra o terminal |
| WSL: credenciais nao funcionam no Windows | Configure credenciais em ambos: WSL (`~/.aws/`) e Windows (`%USERPROFILE%\.aws\`) |
