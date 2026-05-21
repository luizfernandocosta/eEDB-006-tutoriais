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

# Build + upload dos fontes e dados para S3
./scripts/build-and-upload.sh

# Criar infra via Terraform + compilar + executar WordCount
cd terraform
terraform init
terraform apply -auto-approve

# Monitorar steps (aguardar ambos completarem)
terraform output
```

O Terraform cria 2 steps automaticamente:
- **Step1-Compile-JAR**: Compila Java no cluster EMR usando `javac` + `hadoop classpath`
- **Step2-WordCount-And-Copy**: Baixa JAR, copia input do S3 para HDFS, roda MapReduce, copia resultado para S3

> **Nota**: O cluster permanece vivo apos os steps (`keep_job_flow_alive_when_no_steps = true`). Destrua com `terraform destroy` ao terminar.

### Modo CLI (scripts diretos)

```bash
cd ~/Documents/Big\ Data/tutoriais/aws-emr-hadoop-tutorial

# Build + upload
./scripts/build-and-upload.sh

# Criar cluster + compilar + rodar WordCount + mostrar resultados
./scripts/run-wordcount-emr.sh full
```

---

## 2. Ver Resultados

```bash
# Listar arquivos de saida no S3
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3 ls s3://${ACCOUNT_ID}-emr-lab-wordcount/output/

# Top 20 palavras
aws s3 cp s3://${ACCOUNT_ID}-emr-lab-wordcount/output/part-r-00000 - | sort -t$'\t' -k2 -nr | head -20

# Baixar resultados para maquina local
aws s3 sync s3://${ACCOUNT_ID}-emr-lab-wordcount/output/ ./results/
```

**Resultado esperado:**

```
_SUCCEEDED
part-r-00000
```

```
the     60
a       47
of      38
and     30
...
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
hdfs dfs -ls /output/wordcount
hdfs dfs -cat /output/wordcount/part-r-00000 | head -20
yarn application -list -appStates ALL
exit
```

> **Atencao**: No Learner Lab, o SSH pode ter timeout se o security group nao estiver liberado para seu IP. Veja `SSH.md` para troubleshooting.

---

## 4. Monitorar Steps

```bash
./scripts/run-wordcount-emr.sh status

# Ou diretamente:
CLUSTER_ID=$(terraform output -raw cluster_id)
aws emr list-steps --cluster-id $CLUSTER_ID \
    --query 'Steps[].{Name:Name,State:Status.State}' \
    --output table
```

---

## 5. Descomissionamento

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

---

## Bugs Conhecidos e Solucoes

| Bug | Sintoma | Solucao |
|-----|---------|---------|
| `hadoop jar s3://...` em `bash -c` | "JAR does not exist" com path local | Baixar JAR antes: `aws s3 cp s3://...jar /tmp/...jar && hadoop jar /tmp/...jar` |
| `--job-flow-role` | "Unknown parameter" no AWS CLI v2 | Usar `--ec2-attributes InstanceProfile=EMR_EC2_DefaultRole` |
| `MapReduce` application | `ValidationException` | Usar apenas `Name=Hadoop` |
| `s3-dist-cp` HDFS→S3 | Falha silenciosa | Usar `hdfs dfs -copyToLocal` + `aws s3 cp` |
| Step COMPLETED sem output | `;` ignora erros no bash | Usar `&&` para encadear comandos |
