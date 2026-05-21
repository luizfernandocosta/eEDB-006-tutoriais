# Quick Tutorial: WordCount no AWS EMR (Automatico)

> Execute tudo com scripts automatizados. Terraform para infra, scripts para build/upload/run.

---

## 0. Pre-requisitos

AWS CLI e Terraform instalados e credenciais configuradas:

```bash
aws sts get-caller-identity
terraform version
```

Se nao tiver, rode `../install_aws_pre_req/install.sh` e `../install_aws_pre_req/setup_aws_credentials.sh`.

---

## 1. Execucao Completa (um comando)

### Modo Terraform (recomendado)

```bash
cd ~/Documents/Big\ Data/tutoriais/aws-emr-hadoop-tutorial

# Build do JAR + upload para S3
./scripts/build-and-upload.sh

# Criar infra via Terraform + executar WordCount
cd terraform
terraform init
terraform apply -auto-approve

# Aguardar cluster e steps (monitorar)
terraform output
```

### Modo CLI (scripts diretos)

```bash
cd ~/Documents/Big\ Data/tutoriais/aws-emr-hadoop-tutorial

# Build + upload
./scripts/build-and-upload.sh

# Criar cluster + rodar WordCount + mostrar resultados
./scripts/run-wordcount-emr.sh full
```

---

## 2. Ver Resultados

```bash
# Listar arquivos de saida no S3
./scripts/run-wordcount-emr.sh results

# Ou diretamente:
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3 ls s3://${ACCOUNT_ID}-emr-lab-wordcount/output/

# Top 20 palavras
aws s3 cp s3://${ACCOUNT_ID}-emr-lab-wordcount/output/part-r-00000 - | sort -t$'\t' -k2 -nr | head -20

# Baixar resultados para maquina local
aws s3 sync s3://${ACCOUNT_ID}-emr-lab-wordcount/output/ ./results/
```

---

## 3. Acessar o Cluster via SSH

```bash
./scripts/run-wordcount-emr.sh ssh

# Ou manualmente:
CLUSTER_ID=$(cat .cluster_id)
MASTER_DNS=$(aws emr describe-cluster --cluster-id $CLUSTER_ID --query 'Cluster.MasterPublicDnsName' --output text)
ssh -i ~/.ssh/labsuser.pem -o StrictHostKeyChecking=no hadoop@$MASTER_DNS
```

Dentro do master node:

```bash
hdfs dfs -ls /input
hdfs dfs -ls /output
hdfs dfs -cat /output/wordcount/part-r-00000 | head -20
yarn application -list
```

---

## 4. Descomissionamento

```bash
# Remover tudo (cluster + S3 + Terraform)
./scripts/destroy.sh

# Ou seletivamente:
./scripts/destroy.sh cluster   # Apenas cluster EMR
./scripts/destroy.sh s3        # Apenas bucket S3

# Ou via Terraform:
cd terraform && terraform destroy -auto-approve
```

> **IMPORTANTE**: Sempre destrua o cluster ao terminar. Custo do m4.large: ~$0.10/hora por instancia (2 instancias = ~$0.20/hora).
