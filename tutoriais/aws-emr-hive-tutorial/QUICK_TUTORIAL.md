# Quick Tutorial: Hive no AWS EMR (Automatico)

> Execute tudo com Terraform. Infra sobe, EMR roda Hive com dados no S3 e HDFS, resultados sao salvos automaticamente.

---

## 0. Pre-requisitos

```bash
aws sts get-caller-identity
terraform version
```

Se nao tiver, rode `../install_aws_pre_req/install.sh` e `../install_aws_pre_req/setup_aws_credentials.sh`.

---

## 1. Execucao Completa (um comando)

```bash
cd ~/Documents/Big\ Data/tutoriais/aws-emr-hive-tutorial
```

### 1.1 Inicializar o Terraform

```bash
cd terraform
terraform init
```

### 1.2 Ver o que sera criado

```bash
terraform plan
```

O plano deve mostrar:
- 1 S3 bucket
- 6 CSVs + 2 scripts HQL + 1 bootstrap = 9 S3 objects
- 1 EMR cluster com Hive (5 steps automaticos)

### 1.3 Criar tudo (apply)

```bash
terraform apply -auto-approve
```

> **Atencao**: O cluster EMR custa ~$0.20/hora (2x m4.large). Destrua ao terminar!

**Tempo estimado**: ~4 minutos para provisionamento + ~6 minutos para os steps Hive (total ~10 min).

### 1.4 Ver outputs

```bash
terraform output
```

**Resultado esperado:**

```
cluster_id        = "j-XXXXXXXXXXXXX"
master_dns        = "ec2-xx-xx-xx-xx.compute-1.amazonaws.com"
s3_bucket         = "XXXXXXXXXXXX-emr-lab-hive"
s3_results_path   = "s3://XXXXXXXXXXXX-emr-lab-hive/results/s3/"
hdfs_results_path = "hdfs:///data/hdfs/output/"
```

---

## 2. Aguardar os Steps EMR

O apply cria o cluster e ja envia os 5 steps EMR. Os steps rodam em background enquanto o cluster esta WAITING. Verifique o progresso:

```bash
cd terraform
CLUSTER_ID=$(terraform output -raw cluster_id)
aws emr list-steps --cluster-id $CLUSTER_ID \
    --query 'Steps[].{Name:Name,State:Status.State}' --output table
```

Repita o comando acima a cada 30 segundos. **Resultado esperado (todos completos):**

```
| Show-Results                  |  COMPLETED |
| Copy-HDFS-results-to-S3       |  COMPLETED |
| Hive-HDFS-Tables              |  COMPLETED |
| Copy-data-to-HDFS             |  COMPLETED |
| Hive-S3-Tables                |  COMPLETED |
```

Tempo estimado: ~6 minutos para os 5 steps.

---

## 3. Ver Resultados no S3

```bash
cd terraform
BUCKET=$(terraform output -raw s3_bucket)

# Resultados S3 (workflow S3)
echo "=== Resultados S3 ==="
aws s3 ls s3://${BUCKET}/results/s3/
echo ""

# Hive gera nome de arquivo com timestamp — use sync em vez de cp direto
aws s3 sync s3://${BUCKET}/results/s3/ /tmp/results-s3/
cat /tmp/results-s3/000000_0* | column -t -s','
rm -rf /tmp/results-s3/

echo ""

# Resultados HDFS copiados para S3 (workflow HDFS)
echo "=== Resultados HDFS (copiados para S3) ==="
aws s3 ls s3://${BUCKET}/results/hdfs/
echo ""
aws s3 cp s3://${BUCKET}/results/hdfs/000000_0 - | column -t -s','

# Baixar para maquina local
mkdir -p results
aws s3 sync s3://${BUCKET}/results/ results/
echo ""
echo "Resultados salvos em: results/"
ls -la results/
```

---

> **Guia completo de SSH**: [SSH.md](SSH.md) — instrucoes detalhadas para dentro e fora do Learner Lab, troubleshooting, e localizacao da chave PEM.

## 4. Acessar o Cluster via SSH

### Dentro do Learner Lab (terminal embutido)

O Learner Lab fornece um terminal no proprio navegador (painel esquerdo ou AWS CloudShell). Esse terminal ja esta na mesma rede do cluster e possui a chave `vockey` pre-instalada.

1. A chave PEM ja esta em `tutoriais/aws_credenciais/labsuser.pem` (baixada durante a configuracao inicial)
2. No terminal do lab (ou CloudShell), execute:

```bash
# Obter o DNS do master node
CLUSTER_ID=$(terraform output -raw cluster_id)
MASTER_DNS=$(aws emr describe-cluster --cluster-id $CLUSTER_ID \
    --query 'Cluster.MasterPublicDnsName' --output text)
echo $MASTER_DNS

# Conectar via SSH (a chave ja existe no terminal do lab)
ssh -i ~/.ssh/labsuser.pem -o StrictHostKeyChecking=no hadoop@$MASTER_DNS
```

Exploracao dentro do master:

```bash
# Ver tabelas Hive
hive -e 'SHOW TABLES;'

# Workflow S3
hive -e 'SELECT * FROM resultado_vendas_s3;'

# Workflow HDFS
hive -e 'SELECT * FROM resultado_vendas_hdfs;'

# Arquivos HDFS
hdfs dfs -ls /data/hdfs/
hdfs dfs -ls /data/hdfs/output/
hdfs dfs -cat /data/hdfs/output/000000_0

# Sair
exit
```

### Fora do Learner Lab (conta AWS propria)

O EMR cria um security group publico que ja permite SSH de `0.0.0.0/0` por padrao. A chave `vockey` ja esta associada ao cluster no `main.tf`. Basta ter o PEM local e o DNS do master:

```bash
MASTER_DNS=$(terraform output -raw master_dns)
ssh -i ~/Documents/Big\ Data/tutoriais/aws_credenciais/labsuser.pem \
    -o StrictHostKeyChecking=no hadoop@$MASTER_DNS
```

**Importante**: Se estiver em uma conta AWS propria (nao Learner Lab), garanta que o security group do master node permita SSH na porta 22 do seu IP:

```bash
# Descobrir o security group do master
SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=ElasticMapReduce-Master-Public*" \
    --query 'SecurityGroups[0].GroupId' --output text)

# Adicionar regra SSH do seu IP
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp --port 22 \
    --cidr $(curl -s ifconfig.me)/32
```

---

## 5. Descomissionamento

```bash
cd ~/Documents/Big\ Data/tutoriais/aws-emr-hive-tutorial

# Via script (recomendado)
./scripts/destroy.sh

# Ou via Terraform diretamente
cd terraform && terraform destroy -auto-approve
```

> **IMPORTANTE**: Sempre destrua o cluster ao terminar. Custo: ~$0.20/hora (2x m4.large). Nao deixe recursos rodando sem necessidade.

---

## 6. Troubleshooting Rapido

| Problema | Solucao |
|---|---|
| Cluster fica em STARTING >15 min | Verifique orcamento do lab e regiao |
| Step FAILED | `aws emr list-steps --cluster-id $ID --query 'Steps[].{Name:Name,State:Status.State}'` |
| Bucket ja existe | Nome inclui Account ID, garanta que e unico |
| Hive table not found | Hive pode ter falhado no step. Verifique logs: `aws emr describe-step --cluster-id $ID --step-id $STEP_ID` |
| vockey nao encontrado | Crie uma key pair vockey ou use outra e atualize o main.tf |
