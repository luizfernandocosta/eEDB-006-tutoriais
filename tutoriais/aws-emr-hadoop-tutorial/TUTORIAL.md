# Tutorial Completo: WordCount MapReduce no AWS EMR com Terraform

> Guia passo a passo para executar o mesmo WordCount do tutorial Docker, agora na AWS usando EMR (Elastic MapReduce), S3 e Terraform.

---

## Sumario

1. [Visao Geral](#1-visao-geral)
2. [Arquitetura](#2-arquitetura)
3. [Pre-requisitos](#3-pre-requisitos)
4. [Entendendo o AWS EMR](#4-entendendo-o-aws-emr)
5. [Estrutura do Projeto](#5-estrutura-do-projeto)
6. [Passo 1 — Configurar credenciais AWS](#6-passo-1--configurar-credenciais-aws)
7. [Passo 2 — Entender os arquivos Java (MapReduce)](#7-passo-2--entender-os-arquivos-java)
8. [Passo 3 — Preparar arquivos (compilacao local ou no EMR)](#8-passo-3--preparar-arquivos)
9. [Passo 4 — Criar bucket S3 e fazer upload](#9-passo-4--criar-bucket-s3-e-fazer-upload)
10. [Passo 5 — Entender a infraestrutura Terraform](#10-passo-5--entender-a-infraestrutura-terraform)
11. [Passo 6 — Criar o cluster EMR com Terraform](#11-passo-6--criar-o-cluster-emr-com-terraform)
12. [Passo 7 — Monitorar o cluster](#12-passo-7--monitorar-o-cluster)
13. [Passo 8 — Submeter jobs manualmente](#13-passo-8--submeter-jobs-manualmente)
14. [Passo 9 — Ver resultados](#14-passo-9--ver-resultados)
15. [Passo 10 — Acessar o cluster via SSH](#15-passo-10--acessar-o-cluster-via-ssh)
16. [Passo 11 — Descomissionamento](#16-passo-11--descomissionamento)
17. [Comparativo: Docker vs EMR](#17-comparativo-docker-vs-emr)
18. [Custos e Orcamento](#18-custos-e-orcamento)
19. [Troubleshooting](#19-troubleshooting)

---

## 1. Visao Geral

Este tutorial replica o **WordCount MapReduce** do tutorial Docker, mas rodando em um cluster real na AWS usando **Amazon EMR** (Elastic MapReduce).

| Aspecto | Docker (Tutorial anterior) | AWS EMR (Este tutorial) |
|---|---|---|
| **Ambiente** | Container local | Cluster real na AWS |
| **Nos** | Single node (1 container) | Multi-node (1 master + 1 core) |
| **Armazenamento** | HDFS local (volume Docker) | S3 + HDFS distribuido |
| **Infraestrutura** | `docker compose up` | Terraform + AWS CLI |
| **Custo** | Gratuito | ~$0.20/hora (2x m4.large) |
| **Escalabilidade** | 1 no | N nos (ate o limite do lab) |
| **Regiao** | Local | us-east-1 |

### O que voce vai aprender

- Como usar **Terraform** para criar infraestrutura AWS
- Como o **Amazon S3** substitui o HDFS como armazenamento
- Como o **Amazon EMR** provisiona um cluster Hadoop gerenciado
- Como submeter **jobs MapReduce** em um cluster real
- Como monitorar e gerenciar recursos na nuvem

---

## 2. Arquitetura

```
Seu computador                     AWS Cloud (us-east-1)
===============                    =====================

                        +-------+
                        |  S3   | <--- input/ (lorem.txt)
                        |Bucket | <--- jars/ (wordcount.jar)
                        +---+---+
                            |
                    +-------+-------+
                    |               |
              +-----+-----+  +-----+-----+
              |  Master    |  |   Core    |
              |  Node      |  |   Node    |
              | (m4.large) |  | (m4.large)|
              |            |  |           |
              | NameNode   |  | DataNode  |
              | ResourceMgr|  | NodeMgr   |
              +-----+------+  +-----------+
                    |
              Steps executados:
              1. s3-dist-cp: S3 -> HDFS
              2. WordCount MapReduce
              3. s3-dist-cp: HDFS -> S3
```

### Fluxo de dados

```
1. Upload:   Seu PC -> S3 (input/ + jars/)
2. Step 1:   S3 input/ -> HDFS /input/     (s3-dist-cp)
3. Step 2:   HDFS /input/ -> HDFS /output/  (WordCount MapReduce)
4. Step 3:   HDFS /output/ -> S3 output/    (s3-dist-cp)
5. Download: S3 output/ -> Seu PC
```

---

## 3. Pre-requisitos

| Requisito | Como verificar | Como instalar |
|---|---|---|
| AWS CLI v2 | `aws --version` | `../install_aws_pre_req/install.sh` |
| Terraform | `terraform version` | `../install_aws_pre_req/install.sh` |
| Java JDK 8+ | `javac -version` | `../install_aws_pre_req/install.sh` (opcional — pode compilar no EMR) |
| Credenciais AWS | `aws sts get-caller-identity` | `../install_aws_pre_req/setup_aws_credentials.sh` |

### Sobre o ambiente Learner Lab

Este tutorial foi desenhado para o **AWS Academy Learner Lab** com as seguintes restricoes:

| Restricao | Valor | Impacto |
|---|---|---|
| Regioes permitidas | us-east-1, us-west-2 | Usamos us-east-1 |
| Tipos de instancia | nano, micro, small, medium, large | Usamos m4.large |
| Max instancias concorrentes | 9 | Cluster usa 2 (1 master + 1 core) |
| Max vCPUs | 32 | m4.large = 2 vCPUs cada = 4 total |
| EMR roles | EMR_DefaultRole, EMR_EC2_DefaultRole | Ja pre-criadas |
| Key pair | vockey | Ja pre-criado |
| Custo | Orcamento limitado | m4.large ~$0.10/hora cada |

> **Atencao**: O cluster EMR sera **encerrado automaticamente** quando a sessao do lab expirar. Resultados sao salvos no S3 e persistem.

---

## 4. Entendendo o AWS EMR

### O que e o EMR?

**Amazon EMR** (Elastic MapReduce) e um servico gerenciado da AWS que provisiona clusters Hadoop/Spark prontos para uso. Voce nao precisa instalar nem configurar nada — a AWS faz isso automaticamente.

### Comparacao com o tutorial Docker

| Conceito | Docker Local | AWS EMR |
|---|---|---|
| Provisionamento | `docker compose up` | Terraform / AWS CLI |
| Configuracao | Dockerfile + XML | Release label EMR |
| Armazenamento | HDFS (volume Docker) | S3 + HDFS |
| Submissao de job | `hadoop jar ...` | Steps do EMR |
| Monitoramento | Web UI (localhost:8088) | Console AWS + Web UI |
| Escalabilidade | 1 no | N nos |

### Componentes do EMR

```
Cluster EMR
├── Master Node (1)
│   ├── NameNode (HDFS) - gerencia metadados
│   ├── ResourceManager (YARN) - escalona jobs
│   └── Application History Server
├── Core Nodes (1-N)
│   ├── DataNode (HDFS) - armazena dados
│   └── NodeManager (YARN) - executa tarefas
└── Task Nodes (0-N) [opcional]
    └── NodeManager (YARN) - apenas executa tarefas
```

### Tipos de instancia no nosso cluster

| No | Tipo | vCPUs | RAM | Custo/hora |
|---|---|---|---|---|
| Master | m4.large | 2 | 8 GB | ~$0.10 |
| Core | m4.large | 2 | 8 GB | ~$0.10 |
| **Total** | **2 instancias** | **4 vCPUs** | **16 GB** | **~$0.20/hora** |

---

## 5. Estrutura do Projeto

```
tutoriais/aws-emr-hadoop-tutorial/
├── TUTORIAL.md              # Este arquivo
├── QUICK_TUTORIAL.md        # Guia rapido (automatizado)
├── src/                     # Codigo Java MapReduce
│   ├── WordCountMapper.java
│   ├── WordCountReducer.java
│   └── WordCountApplication.java
├── data/                    # Dados de entrada
│   └── lorem.txt
├── terraform/               # Infraestrutura como codigo
│   ├── versions.tf          # Versao do provider AWS
│   ├── main.tf              # S3 bucket + EMR cluster
│   └── outputs.tf           # Outputs (cluster ID, DNS, etc)
├── scripts/
│   ├── build-and-upload.sh  # Compila JAR + upload para S3
│   ├── run-wordcount-emr.sh # Cria cluster + roda WordCount
│   └── destroy.sh           # Descomissionamento completo
├── build/                   # (gerado) JAR compilado
└── results/                 # (gerado) Resultados baixados
```

---

## 6. Passo 1 — Configurar credenciais AWS

### Verificar conectividade

```bash
aws sts get-caller-identity
```

**Resultado esperado:**

```json
{
    "UserId": "AROA...",
    "Account": "849967252385",
    "Arn": "arn:aws:sts::849967252385:assumed-role/voclabs/user..."
}
```

### Verificar roles EMR

```bash
aws iam list-roles --query 'Roles[?RoleName==`EMR_DefaultRole` || RoleName==`EMR_EC2_DefaultRole`].RoleName'
```

**Resultado esperado:**

```json
[
    "EMR_DefaultRole",
    "EMR_EC2_DefaultRole"
]
```

### Verificar key pair

```bash
aws ec2 describe-key-pairs --query 'KeyPairs[].KeyName'
```

**Resultado esperado:**

```json
[
    "vockey"
]
```

Se algum desses comandos falhar, verifique as credenciais com `../install_aws_pre_req/setup_aws_credentials.sh`.

---

## 7. Passo 2 — Entender os arquivos Java

Os arquivos Java sao **identicos** ao tutorial Docker. Nao precisa mudar nada no codigo MapReduce — ele funciona tanto em Hadoop local quanto no EMR.

### WordCountMapper.java

```java
// Divide cada linha em palavras e emite (palavra, 1)
public void map(Object key, Text value, Context context) {
    StringTokenizer itr = new StringTokenizer(value.toString());
    while (itr.hasMoreTokens()) {
        word.set(itr.nextToken());
        context.write(word, one);
    }
}
```

### WordCountReducer.java

```java
// Soma todas as contagens de cada palavra
public void reduce(Text key, Iterable<IntWritable> values, Context context) {
    int sum = 0;
    for (IntWritable val : values) {
        sum += val.get();
    }
    result.set(sum);
    context.write(key, result);
}
```

### WordCountApplication.java

```java
// Configura e submete o job MapReduce
public static void main(String[] args) {
    Configuration conf = new Configuration();
    Job job = Job.getInstance(conf, "WordCount");
    job.setJarByClass(WordCountApplication.class);
    job.setMapperClass(WordCountMapper.class);
    job.setCombinerClass(WordCountReducer.class);
    job.setReducerClass(WordCountReducer.class);
    job.setOutputKeyClass(Text.class);
    job.setOutputValueClass(IntWritable.class);
    FileInputFormat.addInputPath(job, new Path(args[0]));
    FileOutputFormat.setOutputPath(job, new Path(args[1]));
    System.exit(job.waitForCompletion(true) ? 0 : 1);
}
```

> **Ponto-chave**: O `args[0]` e `args[1]` sao os caminhos de entrada/saida que passaremos ao submeter o job. No Docker, eram caminhos HDFS. No EMR, podemos usar tanto HDFS quanto S3.

---

## 8. Passo 3 — Preparar arquivos (compilacao local ou no EMR)

Existem **duas opcoes** para compilar o JAR WordCount. O cluster EMR ja possui Java e Hadoop instalados, entao a compilacao no proprio cluster e a opcao mais simples.

### Opcao A: Compilar no cluster EMR (recomendado, sem pre-requisitos)

Nao precisa ter Java instalado localmente. O script `run-wordcount-emr.sh` detecta automaticamente se o JAR existe no S3 e, se nao existir, adiciona um step de compilacao no cluster EMR usando o Java e o Hadoop que ja estao instalados la.

```bash
# Apenas faca upload dos fontes e dados — o EMR compila
./scripts/build-and-upload.sh
./scripts/run-wordcount-emr.sh full
```

O que acontece automaticamente:
1. Os fontes `.java` sao enviados ao S3 (`s3://bucket/src/`)
2. O cluster EMR e criado
3. Um step compila os fontes usando `javac` + `hadoop classpath` do cluster
4. O JAR resultante e enviado de volta ao S3 (`s3://bucket/jars/wordcount.jar`)
5. Os steps de WordCount sao executados normalmente

### Opcao B: Compilar localmente (requer Java JDK 8+)

Se preferir compilar na sua maquina, instale o Java JDK:

```bash
# Instalar via script de prereqs
./install_aws_pre_req/install.sh

# Ou manualmente:
# macOS:  brew install openjdk@11
# Linux:  sudo apt install openjdk-11-jdk
```

Verifique:

```bash
javac -version
# javac 11.x.x
```

Compile com os JARs do Hadoop:

```bash
mkdir -p build

# Baixar hadoop-client JARs
curl -sL "https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-client-runtime/3.3.6/hadoop-client-runtime-3.3.6.jar" -o build/hadoop-client-runtime.jar
curl -sL "https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-client/3.3.6/hadoop-client-3.3.6.jar" -o build/hadoop-client.jar

# Compilar
javac -classpath "build/hadoop-client.jar:build/hadoop-client-runtime.jar" \
    -d build/ src/*.java

# Empacotar em JAR
cd build && jar cf wordcount.jar *.class && cd ..
```

### Script automatizado (ambas as opcoes)

```bash
./scripts/build-and-upload.sh
```

Este script:
- Se `javac` estiver disponivel: compila localmente e faz upload do JAR
- Se `javac` NAO estiver disponivel: faz upload dos fontes `.java` para compilacao no EMR

---

## 9. Passo 4 — Criar bucket S3 e fazer upload

O **Amazon S3** e o servico de armazenamento de objetos da AWS. Vamos usa-lo para:
1. Armazenar os fontes Java e/ou o JAR compilado
2. Armazenar os dados de entrada (lorem.txt)
3. Receber os resultados do WordCount

### Metodo automatizado (recomendado)

```bash
./scripts/build-and-upload.sh
```

Este script faz tudo: cria o bucket, compila (se possivel) e faz upload.

### Metodo manual

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="${ACCOUNT_ID}-emr-lab-wordcount"

# Criar bucket
aws s3 mb s3://${BUCKET}

# Upload dos dados
aws s3 cp data/lorem.txt s3://${BUCKET}/input/lorem.txt

# Upload do JAR compilado localmente (se tiver)
aws s3 cp build/wordcount.jar s3://${BUCKET}/jars/wordcount.jar

# OU upload dos fontes para compilacao no EMR
aws s3 cp src/ s3://${BUCKET}/src/ --recursive
```

### Verificar o upload

```bash
aws s3 ls s3://${BUCKET}/ --recursive
```

---

## 10. Passo 5 — Entender a infraestrutura Terraform

### O que e Terraform?

**Terraform** e uma ferramenta de **Infraestrutura como Codigo (IaC)**. Em vez de clicar no console AWS, voce descreve a infraestrutura em arquivos de configuracao e o Terraform cria tudo automaticamente.

Analogia: Se o Dockerfile e a "receita" para um container, o Terraform e a "receita" para a infraestrutura cloud.

### Arquivo: terraform/versions.tf

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
```

| Linha | O que faz |
|---|---|
| `required_providers` | Diz ao Terraform que vamos usar o provider da AWS |
| `version = "~> 5.0"` | Usa versao 5.x (qualquer patch) |
| `provider "aws"` | Configura a regiao e as credenciais (lidas de `~/.aws/`) |

### Arquivo: terraform/main.tf (explicacao)

#### S3 Bucket

```hcl
resource "aws_s3_bucket" "emr_lab" {
  bucket        = "emr-lab-wordcount-${data.aws_caller_identity.current.account_id}"
  force_destroy = true    # Permite deletar mesmo com objetos dentro
}
```

#### Upload de arquivos via Terraform

```hcl
resource "aws_s3_object" "wordcount_jar" {
  bucket = aws_s3_bucket.emr_lab.id
  key    = "jars/wordcount.jar"          # Caminho no S3
  source = "${path.module}/../build/wordcount.jar"  # Arquivo local
  etag   = filemd5(...)                  # Re-upload se mudar
}
```

> O Terraform tambem faz o upload dos arquivos para o S3! Nao precisa rodar `aws s3 cp` manualmente se usar Terraform.

#### Cluster EMR

```hcl
resource "aws_emr_cluster" "wordcount" {
  name          = "wordcount-emr-cluster"
  release_label = "emr-6.15.0"          # Versao do EMR (Hadoop 3.x)
  applications  = ["Hadoop", "MapReduce"]

  service_role = "EMR_DefaultRole"       # Role para o servico EMR
  ec2_attributes {
    key_name     = "vockey"              # Chave SSH
    service_role = "EMR_EC2_DefaultRole" # Role para as instancias EC2
  }

  master_instance_group {
    instance_type = "m4.large"           # Tipo da instancia master
    instance_count = 1
  }

  core_instance_group {
    instance_type  = "m4.large"          # Tipo da instancia core
    instance_count = 1
  }
}
```

#### Steps (jobs) do EMR

```hcl
step {
  name = "Copy-input-data-from-S3-to-HDFS"
  hadoop_jar_step {
    jar  = "command-runner.jar"   # Utilitario do EMR
    args = ["s3-dist-cp", "--src", "s3://.../input/", "--dest", "hdfs:///input/"]
  }
}

step {
  name = "Run-WordCount-MapReduce"
  hadoop_jar_step {
    jar  = "s3://.../jars/wordcount.jar"
    args = ["hdfs:///input/", "hdfs:///output/wordcount/"]
  }
}

step {
  name = "Copy-output-from-HDFS-to-S3"
  hadoop_jar_step {
    jar  = "command-runner.jar"
    args = ["s3-dist-cp", "--src", "hdfs:///output/wordcount/", "--dest", "s3://.../output/"]
  }
}
```

> **s3-dist-cp**: Ferramenta otimizada do EMR para copiar dados entre S3 e HDFS. E como o `hdfs dfs -put`/`-get`, mas muito mais rapido para grandes volumes.

---

## 11. Passo 6 — Criar o cluster EMR com Terraform

### Inicializar o Terraform

```bash
cd ~/Documents/Big\ Data/tutoriais/aws-emr-hadoop-tutorial/terraform
terraform init
```

**Resultado esperado:**

```
Initializing the backend...
Initializing provider plugins...
- Installing hashicorp/aws v5.x.x...
Terraform has been successfully initialized!
```

### Ver o que sera criado (plan)

```bash
terraform plan
```

O Terraform mostrara tudo que vai criar:
- 1 S3 bucket
- 3 S3 objects (JAR, dados, bootstrap script)
- 1 EMR cluster com 3 steps

### Criar tudo (apply)

```bash
terraform apply -auto-approve
```

> **Atencao**: Isso criara recursos que custam dinheiro. O cluster EMR custa ~$0.20/hora.

**Tempo de provisionamento**: 5-10 minutos. O Terraform retornara quando o cluster estiver em estado WAITING (pronto para receber jobs).

### Ver os outputs

```bash
terraform output
```

**Resultado esperado:**

```
cluster_id = "j-XXXXXXXXXXXXX"
cluster_master_public_dns = "ec2-xx-xx-xx-xx.compute-1.amazonaws.com"
s3_bucket = "emr-lab-wordcount-849967252385"
s3_output_path = "s3://emr-lab-wordcount-849967252385/output/"
```

---

## 12. Passo 7 — Monitorar o cluster

### Via AWS CLI

```bash
# Status do cluster
aws emr describe-cluster --cluster-id j-XXXXXXXXXXXXX \
    --query 'Cluster.{Name:Name,State:Status.State,Master:MasterPublicDnsName}'

# Listar steps e seus estados
aws emr list-steps --cluster-id j-XXXXXXXXXXXXX \
    --query 'Steps[].{Name:Name,State:Status.State}' \
    --output table
```

### Via Console AWS

1. Acesse: https://console.aws.amazon.com/elasticmapreduce/
2. Clique no cluster "wordcount-emr-cluster"
3. Veja a aba "Steps" para o progresso dos jobs
4. Veja a aba "Hardware" para as instancias

### Web UI do Hadoop

```bash
# Criar tunel SSH para a Web UI
CLUSTER_ID=$(terraform output -raw cluster_id)
MASTER_DNS=$(terraform output -raw cluster_master_public_dns)

ssh -i ~/.ssh/labsuser.pem -N -L 8088:localhost:8088 hadoop@$MASTER_DNS &
```

Acesse: http://localhost:8088 (YARN ResourceManager)

> Para o HDFS NameNode: `-L 9870:localhost:9870` e acesse http://localhost:9870

---

## 13. Passo 8 — Submeter jobs manualmente (sem Terraform)

Se quiser submeter steps manualmente a um cluster ja existente:

### Criar cluster sem steps

```bash
CLUSTER_ID=$(aws emr create-cluster \
    --name "wordcount-manual" \
    --release-label "emr-6.15.0" \
    --applications Name=Hadoop Name=MapReduce \
    --service-role "EMR_DefaultRole" \
    --job-flow-role "EMR_EC2_DefaultRole" \
    --ec2-attributes KeyName=vockey \
    --instance-groups \
        '[{"InstanceGroupType":"MASTER","InstanceCount":1,"InstanceType":"m4.large","Name":"Master"},
          {"InstanceGroupType":"CORE","InstanceCount":1,"InstanceType":"m4.large","Name":"Core"}]' \
    --no-auto-terminate \
    --query 'ClusterId' --output text)

echo "Cluster ID: $CLUSTER_ID"
```

### Submeter step: copiar S3 -> HDFS

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="${ACCOUNT_ID}-emr-lab-wordcount"

aws emr add-steps --cluster-id $CLUSTER_ID --steps \
    '[{"Name":"Copy-S3-to-HDFS","ActionOnFailure":"CONTINUE","HadoopJarStep":{"Jar":"command-runner.jar","Args":["s3-dist-cp","--src","s3://'${BUCKET}'/input/","--dest","hdfs:///input/"]}}]'
```

### Submeter step: WordCount

```bash
aws emr add-steps --cluster-id $CLUSTER_ID --steps \
    '[{"Name":"WordCount","ActionOnFailure":"CONTINUE","HadoopJarStep":{"Jar":"s3://'${BUCKET}'/jars/wordcount.jar","Args":["hdfs:///input/","hdfs:///output/wordcount/"]}}]'
```

### Submeter step: copiar HDFS -> S3

```bash
aws emr add-steps --cluster-id $CLUSTER_ID --steps \
    '[{"Name":"Copy-HDFS-to-S3","ActionOnFailure":"CONTINUE","HadoopJarStep":{"Jar":"command-runner.jar","Args":["s3-dist-cp","--src","hdfs:///output/wordcount/","--dest","s3://'${BUCKET}'/output/"]}}]'
```

### Verificar estado dos steps

```bash
aws emr list-steps --cluster-id $CLUSTER_ID \
    --query 'Steps[].{Name:Name,State:Status.State}' \
    --output table
```

---

## 14. Passo 9 — Ver resultados

### Listar arquivos de saida

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="${ACCOUNT_ID}-emr-lab-wordcount"

aws s3 ls s3://${BUCKET}/output/
```

**Resultado esperado:**

```
2026-05-21 ...          0  _SUCCESS
2026-05-21 ...       XXXX  part-r-00000
```

### Ver o conteudo (top 20 palavras)

```bash
aws s3 cp s3://${BUCKET}/output/part-r-00000 - | sort -t$'\t' -k2 -nr | head -20
```

### Baixar para maquina local

```bash
mkdir -p results
aws s3 sync s3://${BUCKET}/output/ results/

cat results/part-r-00000 | sort -t$'\t' -k2 -nr | head -20
```

---

## 15. Passo 10 — Acessar o cluster via SSH

### Obter o DNS do master

```bash
CLUSTER_ID=j-XXXXXXXXXXXXX  # Substitua pelo ID real
MASTER_DNS=$(aws emr describe-cluster --cluster-id $CLUSTER_ID \
    --query 'Cluster.MasterPublicDnsName' --output text)
echo "Master DNS: $MASTER_DNS"
```

### Conectar

```bash
ssh -i ~/.ssh/labsuser.pem -o StrictHostKeyChecking=no hadoop@$MASTER_DNS
```

### Comandos uteis dentro do master

```bash
# Ver processos Java
jps

# Listar arquivos no HDFS
hdfs dfs -ls /

# Ver dados de entrada
hdfs dfs -ls /input
hdfs dfs -cat /input/lorem.txt | head -5

# Ver resultados
hdfs dfs -ls /output/wordcount
hdfs dfs -cat /output/wordcount/part-r-00000 | head -20

# Ver jobs YARN
yarn application -list -appStates ALL

# Informacoes do HDFS
hdfs dfsadmin -report

# Sair
exit
```

### Tunel SSH para Web UI

```bash
# YARN ResourceManager (porta 8088)
ssh -i ~/.ssh/labsuser.pem -N -L 8088:localhost:8088 hadoop@$MASTER_DNS &

# HDFS NameNode (porta 9870)
ssh -i ~/.ssh/labsuser.pem -N -L 9870:localhost:9870 hadoop@$MASTER_DNS &
```

Acesse no navegador:
- YARN: http://localhost:8088
- HDFS: http://localhost:9870

Para fechar os tuneis:

```bash
kill $(jobs -p) 2>/dev/null
```

---

## 16. Passo 11 — Descomissionamento

> **IMPORTANTE**: Sempre destrua os recursos ao terminar para evitar custos desnecessarios.

### Via script automatizado

```bash
cd ~/Documents/Big\ Data/tutoriais/aws-emr-hadoop-tutorial
./scripts/destroy.sh
```

### Via Terraform

```bash
cd ~/Documents/Big\ Data/tutoriais/aws-emr-hadoop-tutorial/terraform
terraform destroy -auto-approve
```

### Manualmente

```bash
# Encerrar cluster
aws emr terminate-clusters --cluster-ids j-XXXXXXXXXXXXX

# Esvaziar e remover bucket S3
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3 rm s3://${ACCOUNT_ID}-emr-lab-wordcount --recursive
aws s3 rb s3://${ACCOUNT_ID}-emr-lab-wordcount
```

### Verificar que tudo foi removido

```bash
# Verificar clusters ativos
aws emr list-clusters --cluster-states STARTING BOOTSTRAPPING RUNNING WAITING

# Verificar buckets S3
aws s3 ls | grep wordcount
```

---

## 17. Comparativo: Docker vs EMR

| Aspecto | Docker (Local) | EMR (AWS) |
|---|---|---|
| **Setup** | `docker compose up` | Terraform / AWS CLI |
| **Tempo de setup** | ~30s | ~5-10 min |
| **Custo** | Gratuito | ~$0.20/hora |
| **Nos** | 1 | 2+ |
| **Armazenamento** | HDFS local | S3 (persistente) + HDFS |
| **Compilacao** | Dentro do container | No cluster EMR (ou local com Java JDK) |
| **Submissao de job** | `hadoop jar ...` | EMR Steps ou `hadoop jar` via SSH |
| **Web UI** | localhost:8088 | SSH tunnel + localhost:8088 |
| **Resultados** | HDFS local | S3 (persiste apos cluster) |
| **Escalabilidade** | Limitado pela maquina | Limitado pelo orcamento AWS |
| **Persistencia** | Volume Docker | S3 (eterno) |

### Quando usar cada um?

| Situacao | Recomendacao |
|---|---|
| Aprender Hadoop | Docker (local, gratuito) |
| Testar codigo MapReduce | Docker (rapido) |
| Processar dados reais (>10GB) | EMR (escalavel) |
| Trabalho de producao | EMR ou EMR Serverless |
| Preparar certificacao AWS | EMR (experiencia real) |

---

## 18. Custos e Orcamento

### Estimativa de custo por sessao

| Recurso | Quantidade | Custo/hora | Tempo estimado | Custo |
|---|---|---|---|---|
| Master node (m4.large) | 1 | $0.10 | 30 min | $0.05 |
| Core node (m4.large) | 1 | $0.10 | 30 min | $0.05 |
| S3 storage | ~10 KB | ~$0.00 | - | $0.00 |
| **Total por sessao** | | | | **~$0.10** |

### Dicas para economizar

1. **Sempre destrua o cluster** ao terminar (`./scripts/destroy.sh`)
2. **Use `--auto-terminate`** se nao precisar do cluster apos o job
3. **Resultado salva no S3** — nao precisa manter o cluster para ver resultados
4. **Use instancias menores** para testes (m4.large e o minimo para EMR)

---

## 19. Troubleshooting

| Problema | Causa | Solucao |
|---|---|---|
| `terraform init` falha | Provider AWS nao baixa | Verifique conexao com internet |
| `terraform apply` erro de role | Roles EMR nao existem | As roles sao pre-criadas no Learner Lab. Se nao existir, contate o instrutor |
| Cluster fica em STARTING | Provisionamento lento | Aguarde 5-10 min. Se passar de 15 min, verifique os logs no console |
| Step FAILED | JAR invalido ou input nao encontrado | Verifique se o JAR esta no S3: `aws s3 ls s3://bucket/jars/` |
| `wordcount.jar` e "pending_compile" | Java nao disponivel localmente | Instale Java JDK 8+ ou compile dentro do cluster via SSH |
| `Key pair vockey not found` | Key pair nao existe na regiao | Crie uma key pair ou use outra existente |
| Instance limit exceeded | Mais de 9 instancias rodando | Encerre instancias/EMR clusters nao usados |
| Budget exceeded | Orcamento do lab esgotado | Nao ha recuperacao. Monitore o budget |
| SSH connection refused | Security group sem porta 22 | No EMR, a porta 22 geralmente ja esta aberta |
| `The security token included in the request is expired` | Credenciais expiradas | Re-execute `setup_aws_credentials.sh` |
| S3 bucket already exists | Bucket com mesmo nome em outra conta | O nome inclui o Account ID para evitar conflitos |
| Cluster termina automaticamente | Sessao do lab expirou | Resultados no S3 persistem. Recrie o cluster na proxima sessao |
