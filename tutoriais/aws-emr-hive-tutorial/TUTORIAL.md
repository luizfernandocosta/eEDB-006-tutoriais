# Tutorial Completo: Hive no AWS EMR com Terraform

> Guia passo a passo para criar tabelas Hive, carregar dados CSV (3 arquivos relacionais), executar queries com JOIN e agregacao, e salvar resultados — tanto no S3 quanto no HDFS interno do EMR.

---

## Sumario

1. [Visao Geral](#1-visao-geral)
2. [Arquitetura](#2-arquitetura)
3. [O que e o Hive?](#3-o-que-e-o-hive)
4. [Pre-requisitos](#4-pre-requisitos)
5. [Estrutura do Projeto](#5-estrutura-do-projeto)
6. [Dados de Exemplo](#6-dados-de-exemplo)
7. [Entendendo os arquivos Terraform](#7-entendendo-os-arquivos-terraform)
8. [Passo 1 — Configurar credenciais AWS](#8-passo-1--configurar-credenciais-aws)
9. [Passo 2 — Inicializar o Terraform](#9-passo-2--inicializar-o-terraform)
10. [Passo 3 — Entender o que sera criado (plan)](#10-passo-3--entender-o-que-sera-criado-plan)
11. [Passo 4 — Provisionar tudo (apply)](#11-passo-4--provisionar-tudo-apply)
12. [Passo 5 — Monitorar o cluster e steps](#12-passo-5--monitorar-o-cluster-e-steps)
13. [Passo 6 — Workflow S3: Entendendo o que aconteceu](#13-passo-6--workflow-s3-entendendo-o-que-aconteceu)
14. [Passo 7 — Workflow HDFS: Entendendo o que aconteceu](#14-passo-7--workflow-hdfs-entendendo-o-que-aconteceu)
15. [Passo 8 — Ver os Resultados](#15-passo-8--ver-os-resultados)
16. [Passo 9 — Acessar o cluster via SSH e explorar](#16-passo-9--acessar-o-cluster-via-ssh-e-explorar)
17. [Passo 10 — Descomissionamento](#17-passo-10--descomissionamento)
18. [Custos e Orcamento](#18-custos-e-orcamento)
19. [Troubleshooting](#19-troubleshooting)

---

## 1. Visao Geral

Neste tutorial voce vai criar um cluster **Amazon EMR** com **Apache Hive** usando **Terraform**, e trabalhar com dados de uma loja virtual (clientes, produtos e vendas) em **dois workflows distintos**:

| Workflow | Armazenamento | Persistencia | Mecanismo |
|---|---|---|---|
| **S3** | Bucket S3 | Os dados persistem apos destruir o cluster | Tabelas externas Hive apontando para S3 |
| **HDFS** | HDFS interno do EMR | Dados somem quando o cluster e destruido | Tabelas internas Hive no HDFS |

### O que voce vai aprender

- Criar infraestrutura AWS com **Terraform** (S3 + EMR com Hive)
- Entender a diferenca entre **tabelas externas (S3)** e **tabelas gerenciadas (HDFS)** no Hive
- Escrever **queries HiveQL** com JOIN entre 3 tabelas
- Usar **INSERT OVERWRITE** para gerar arquivos CSV de resultado
- Usar **s3-dist-cp** para copiar dados entre S3 e HDFS
- Monitorar steps do EMR e verificar resultados
- Descomissionar tudo para nao gerar custos

---

## 2. Arquitetura

```
Seu computador                     AWS Cloud (us-east-1)
=================                  =====================

                         +-----------------------+
                         |   S3 Bucket           |
                         |   (dados + scripts)   |
                         |                       |
                         |  data/s3/clientes/    |
                         |  data/s3/produtos/    |
                         |  data/s3/vendas/      |
                         |  data/hdfs/clientes/  |
                         |  data/hdfs/produtos/  |
                         |  data/hdfs/vendas/    |
                         |  hive/setup-s3.hql    |
                         |  hive/setup-hdfs.hql  |
                         |  results/s3/          |
                         |  results/hdfs/        |
                         +----------+------------+
                                    |
                    +---------------+---------------+
                    |                               |
              +-----+-----+                  +-----+-----+
              |  Master    |                  |   Core    |
              |  Node      |                  |   Node    |
              | (m4.large) |                  | (m4.large)|
              |            |                  |           |
              | HDFS NN    |                  | HDFS DN   |
              | YARN RM    |                  | YARN NM   |
              | Hive       |                  |           |
              +-----+------+                  +-----------+
                    |
        Steps executados em sequencia:
        1. Hive S3: CREATE EXTERNAL TABLES + INSERT OVERWRITE (no S3)
        2. s3-dist-cp: Copia CSVs do S3 para HDFS
        3. Hive HDFS: CREATE TABLES + INSERT OVERWRITE (no HDFS)
        4. s3-dist-cp: Copia resultados do HDFS de volta para S3
        5. Show Results: Exibe resultados nos logs
```

### Fluxo de dados

**Workflow S3**:
```
CSVs locais --(Terraform)--> S3 data/s3/ --(Hive)--> Tabelas externas --(INSERT OVERWRITE)--> S3 results/s3/ (CSV)
```

**Workflow HDFS**:
```
CSVs locais --(Terraform)--> S3 data/hdfs/ --(s3-dist-cp)--> HDFS /data/hdfs/ --(Hive)--> Tabelas HDFS --(INSERT OVERWRITE)--> HDFS /data/hdfs/output/ --(s3-dist-cp)--> S3 results/hdfs/ (CSV)
```

---

## 3. O que e o Hive?

### O problema que o Hive resolve

Imagine que voce tem **arquivos CSV** com dados de vendas, clientes e produtos. Sem o Hive, para fazer uma pergunta como _"Qual categoria de produto vende mais em cada estado?"_ voce precisaria escrever um programa Java MapReduce completo — dezenas de linhas de codigo.

Com o Hive, voce escreve **SQL**:

```sql
SELECT c.estado, p.categoria, SUM(v.quantidade * p.preco) AS total
FROM vendas v
JOIN clientes c ON v.id_cliente = c.id_cliente
JOIN produtos p ON v.id_produto = p.id_produto
GROUP BY c.estado, p.categoria;
```

O Hive converte esse SQL em **jobs MapReduce** (ou Tez) automaticamente. Voce nao precisa escrever Mapper, Reducer, nem pensar em paralelizacao.

### Conceitos fundamentais do Hive

| Conceito | Explicacao |
|---|---|
| **Tabela** | Estrutura que organiza dados. Como uma tabela SQL relacional. |
| **Particao** | Divide dados por coluna (ex: por estado). Otimiza queries. |
| **Tabela Externa (EXTERNAL)** | O Hive le os dados de um local que voce especifica (S3, HDFS). Se voce DROPAR a tabela, os dados permanecem. |
| **Tabela Gerenciada (MANAGED)** | O Hive gerencia os dados no warehouse (/user/hive/warehouse/). Se voce DROPAR a tabela, os dados sao apagados. |
| **HiveQL** | Linguagem SQL do Hive. Suporta SELECT, JOIN, GROUP BY, INSERT, etc. |
| **SerDe** | Serializer/Deserializer. Define como ler o arquivo (CSV, JSON, Parquet, etc.). |

### Hive vs SQL tradicional

| SQL Tradicional (MySQL, PostgreSQL) | HiveQL |
|---|---|
| Dados em tabelas proprias | Dados em arquivos (CSV, Parquet, etc.) |
| Transacoes ACID | Orientado a leitura (batch) |
| Milissegundos | Segundos a minutos (MapReduce) |
| Ideal para OLTP | Ideal para analytics (OLAP) |
| Escalabilidade vertical | Escalabilidade horizontal (cluster) |

---

## 4. Pre-requisitos

| Requisito | Como verificar | Como instalar |
|---|---|---|
| AWS CLI v2 | `aws --version` | `../install_aws_pre_req/install.sh` |
| Terraform | `terraform version` | `../install_aws_pre_req/install.sh` |
| Credenciais AWS | `aws sts get-caller-identity` | `../install_aws_pre_req/setup_aws_credentials.sh` |

### Sobre o ambiente Learner Lab

Este tutorial foi desenhado para o **AWS Academy Learner Lab**. Restricoes importantes:

| Restricao | Valor | Impacto no tutorial |
|---|---|---|
| Regioes | us-east-1, us-west-2 | Usamos us-east-1 |
| Tipos de instancia | nano, micro, small, medium, large | Usamos m4.large |
| Max instancias | 9 simultaneas | Cluster usa 2 (master + core) |
| Max vCPUs | 32 | m4.large = 2 vCPUs cada = 4 total |
| Roles EMR | EMR_DefaultRole, EMR_EC2_DefaultRole | Ja pre-criadas |
| Key pair | vockey | Ja pre-criado |
| Custo | Orcamento limitado | m4.large ~$0.10/hora cada |

> **Atencao**: O cluster EMR sera encerrado automaticamente quando a sessao do lab expirar. Resultados salvos no S3 persistem.

---

## 5. Estrutura do Projeto

```
tutoriais/aws-emr-hive-tutorial/
├── TUTORIAL.md                   # Este arquivo (passo a passo detalhado)
├── QUICK_TUTORIAL.md             # Guia rapido (comandos automaticos)
├── data/                         # Dados CSV de entrada
│   ├── clientes.csv              #   15 clientes (id, nome, email, cidade, estado)
│   ├── produtos.csv              #   10 produtos (id, nome, categoria, preco)
│   └── vendas.csv                #   30 vendas (id, id_cliente, id_produto, qtd, data)
├── terraform/                    # Infraestrutura como codigo
│   ├── versions.tf               #   Provider AWS versao 5.x
│   ├── main.tf                   #   S3 bucket + EMR cluster + steps Hive
│   └── outputs.tf                #   Outputs (cluster ID, DNS, bucket, paths)
└── scripts/
    └── destroy.sh                # Descomissionamento completo
```

---

## 6. Dados de Exemplo

Criamos 3 arquivos CSV que representam uma **loja virtual**:

### clientes.csv

| Coluna | Tipo | Exemplo |
|---|---|---|
| id_cliente | INT | 1 |
| nome | STRING | Joao Silva |
| email | STRING | joao@email.com |
| cidade | STRING | Sao Paulo |
| estado | STRING | SP |

15 clientes em 12 estados diferentes.

### produtos.csv

| Coluna | Tipo | Exemplo |
|---|---|---|
| id_produto | INT | 1 |
| nome_produto | STRING | Smartphone X |
| categoria | STRING | Eletronicos |
| preco | DOUBLE | 2500.00 |

10 produtos em 5 categorias: **Eletronicos, Acessorios, Vestuario, Esportes, Livros**.

### vendas.csv

| Coluna | Tipo | Exemplo |
|---|---|---|
| id_venda | INT | 1 |
| id_cliente | INT | 1 |
| id_produto | INT | 1 |
| quantidade | INT | 2 |
| data_venda | STRING | 2026-01-15 |

30 vendas realizadas em Janeiro e Fevereiro de 2026.

### Query que vamos executar

As duas workflows (S3 e HDFS) executam a **mesma query**:

```sql
INSERT OVERWRITE TABLE resultado
SELECT c.estado, p.categoria,
       round(SUM(v.quantidade * p.preco), 2) AS total_vendido,
       COUNT(*) AS num_vendas
FROM vendas v
JOIN clientes c ON v.id_cliente = c.id_cliente
JOIN produtos p ON v.id_produto = p.id_produto
GROUP BY c.estado, p.categoria
ORDER BY total_vendido DESC;
```

**O que a query faz:**
1. Junta (JOIN) as 3 tabelas pelo ID do cliente e ID do produto
2. Agrupa (GROUP BY) por estado e categoria
3. Calcula o total vendido (quantidade x preco) e o numero de vendas
4. Ordena do maior valor para o menor
5. Insere o resultado na tabela de destino, que gera um arquivo CSV

---

## 7. Entendendo os arquivos Terraform

### 7.1 versions.tf

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
| `required_providers` | Declara que vamos usar o provider da AWS |
| `version = "~> 5.0"` | Usa versao 5.x do provider AWS |
| `provider "aws"` | Configura a regiao us-east-1 |

### 7.2 main.tf — Explicacao em partes

#### S3 Bucket

```hcl
resource "aws_s3_bucket" "emr_lab" {
  bucket        = "${ACCOUNT_ID}-emr-lab-hive"
  force_destroy = true
}
```

Cria um bucket S3 com nome unico (baseado no Account ID). O `force_destroy` permite deletar o bucket mesmo com objetos dentro.

#### Upload dos CSVs

```hcl
resource "aws_s3_object" "clientes_s3" {
  bucket = aws_s3_bucket.emr_lab.id
  key    = "data/s3/clientes/clientes.csv"
  source = "data/clientes.csv"
  etag   = filemd5("data/clientes.csv")
}
```

Faz upload do CSV local para o S3. Repetimos para cada arquivo em cada workflow:
- **Workflow S3**: `data/s3/clientes/`, `data/s3/produtos/`, `data/s3/vendas/`
- **Workflow HDFS**: `data/hdfs/clientes/`, `data/hdfs/produtos/`, `data/hdfs/vendas/`

> Por que duplicar os CSVs? Para demonstrar dois workflows independentes: um lendo do S3 diretamente, outro copiando para o HDFS primeiro.

#### Scripts HQL (Hive)

Os scripts HQL sao criados como objetos S3 usando o parametro `content` com heredoc:

```hcl
resource "aws_s3_object" "hive_s3_hql" {
  bucket = aws_s3_bucket.emr_lab.id
  key    = "hive/setup-s3.hql"
  content = <<-HQL
    CREATE EXTERNAL TABLE IF NOT EXISTS clientes_s3 (...)
    LOCATION 's3://BUCKET/data/s3/clientes/'
    ...
    INSERT OVERWRITE TABLE resultado_vendas_s3
    SELECT ...
  HQL
}
```

O conteudo do HQL e inserido diretamente no Terraform. O bucket name e substituido automaticamente via `${local.bucket_name}`.

#### Bootstrap Action

```hcl
resource "aws_s3_object" "bootstrap_script" {
  content = <<-SCRIPT
    #!/bin/bash
    echo "Bootstrap: Configuring environment..."
    # HDFS directories will be created automatically by s3-dist-cp and Hive steps
    echo "Bootstrap complete."
  SCRIPT
}
```

O **bootstrap action** e um script que roda quando o cluster EMR inicia. Ele prepara o ambiente. Neste tutorial o bootstrap e simplificado porque os diretorios HDFS sao criados automaticamente pelo `s3-dist-cp` (Step 2) e pelo `INSERT OVERWRITE` do Hive (Step 3) — nao e necessario criar diretorios manualmente.

#### Cluster EMR

```hcl
resource "aws_emr_cluster" "hive_lab" {
  name          = "hive-emr-cluster"
  release_label = "emr-6.15.0"
  applications  = ["Hadoop", "Hive"]
  ...
}
```

| Parametro | Valor | Explicacao |
|---|---|---|
| `release_label` | emr-6.15.0 | Versao do EMR (inclui Hadoop 3.x + Hive 3.x) |
| `applications` | ["Hadoop", "Hive"] | Servicos instalados no cluster |

#### Steps do EMR

Cada **step** e um job que o EMR executa em sequencia. Nosso cluster tem 5 steps:

**Step 1 — Hive S3**:
```hcl
step {
  name = "Hive-S3-Tables"
  hadoop_jar_step {
    jar  = "command-runner.jar"
    args = ["hive", "-f", "s3://BUCKET/hive/setup-s3.hql"]
  }
}
```
O `command-runner.jar` e um utilitario do EMR que executa comandos no cluster. Aqui ele roda `hive -f` com o script HQL armazenado no S3.

**Step 2 — s3-dist-cp**:
Copia os CSVs da pasta `data/hdfs/` no S3 para o HDFS em `/data/hdfs/`.

**Step 3 — Hive HDFS**:
Executa o script `setup-hdfs.hql` que cria tabelas sobre os dados no HDFS.

**Step 4 — s3-dist-cp**:
Copia os resultados do HDFS de volta para o S3 (persistencia).

**Step 5 — Show Results**:
Exibe os resultados nos logs do step.

---

## 8. Passo 1 — Configurar credenciais AWS

### Verificar conectividade

```bash
aws sts get-caller-identity
```

**Resultado esperado:**

```json
{
    "UserId": "AROA...",
    "Account": "XXXXXXXXXXXX",
    "Arn": "arn:aws:sts::XXXXXXXXXXXX:assumed-role/voclabs/user..."
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

> **Nota**: A chave `vockey` e o nome do key pair na AWS. O arquivo PEM baixado do lab chama-se `labsuser.pem` (mapeamento automatico do Learner Lab). O SSH usa `ssh -i ~/.ssh/labsuser.pem`.

Se algum desses comandos falhar, configure as credenciais:
```bash
../install_aws_pre_req/setup_aws_credentials.sh
```

---

## 9. Passo 2 — Inicializar o Terraform

### Navegar ate a pasta do projeto

```bash
cd ~/Documents/Big\ Data/tutoriais/aws-emr-hive-tutorial/terraform
```

### Inicializar o Terraform

```bash
terraform init
```

**O que acontece:**
1. Terraform baixa o provider AWS (plugin que conversa com a API da AWS)
2. Inicializa o backend (onde o estado e armazenado)
3. Prepara o ambiente para execucao

**Resultado esperado:**

```
Initializing the backend...
Initializing provider plugins...
- Installing hashicorp/aws v5.x.x...
Terraform has been successfully initialized!
```

---

## 10. Passo 3 — Entender o que sera criado (plan)

```bash
terraform plan
```

O Terraform mostra tudo que vai criar sem executar nada. E como um "ensaio geral".

**Resultado esperado (resumido):**

```
Terraform will perform the following actions:

  # aws_s3_bucket.emr_lab will be created
  # aws_s3_object.clientes_s3 will be created
  # aws_s3_object.produtos_s3 will be created
  # aws_s3_object.vendas_s3 will be created
  # aws_s3_object.clientes_hdfs will be created
  # aws_s3_object.produtos_hdfs will be created
  # aws_s3_object.vendas_hdfs will be created
  # aws_s3_object.hive_s3_hql will be created
  # aws_s3_object.hive_hdfs_hql will be created
  # aws_s3_object.bootstrap_script will be created
  # aws_emr_cluster.hive_lab will be created

Plan: 11 to add, 0 to change, 0 to destroy.
```

**11 recursos** serao criados:
- 1 bucket S3
- 6 CSVs (3 S3 + 3 HDFS)
- 2 scripts HQL
- 1 bootstrap script
- 1 cluster EMR

---

## 11. Passo 4 — Provisionar tudo (apply)

```bash
terraform apply -auto-approve
```

> **Atencao**: Isso cria recursos que custam dinheiro. O cluster EMR custa ~$0.20/hora.

**O que acontece durante o apply:**

```
[0s]   Terraform comeca a criar recursos
       - Cria o bucket S3
       - Faz upload dos 6 CSVs
       - Faz upload dos 2 scripts HQL e 1 bootstrap
       - Inicia o cluster EMR

[60s]  Cluster EMR em estado STARTING
       - EC2 instancias sendo provisionadas
       - Bootstrap action executa (script simplificado — diretorios HDFS serao criados pelos steps seguintes)
       - Hadoop, Hive sendo instalados

[5-10min] Cluster atinge estado WAITING
       - Pronto para receber steps
       - Steps comecam a executar automaticamente

[10-12min] Step 1: Hive-S3-Tables
       - Cria tabelas externas no S3
       - Executa INSERT OVERWRITE
       - Resultado vai para S3

[12-14min] Step 2: Copy-data-to-HDFS
       - s3-dist-cp copia CSVs do S3 para HDFS

[14-16min] Step 3: Hive-HDFS-Tables
       - Cria tabelas no HDFS
       - Executa INSERT OVERWRITE
       - Resultado vai para HDFS

[16-17min] Step 4: Copy-HDFS-results-to-S3
       - s3-dist-cp copia resultado do HDFS para S3

[17-18min] Step 5: Show-Results
       - Exibe resultados nos logs

[~18min] Terraform conclui
       - Cluster em estado WAITING
       - Resultados no S3
```

### Ver os outputs

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

Salve o Cluster ID para monitoramento:
```bash
CLUSTER_ID=$(terraform output -raw cluster_id)
echo $CLUSTER_ID
```

---

## 12. Passo 5 — Monitorar o cluster e steps

### Status do cluster

```bash
CLUSTER_ID=$(terraform output -raw cluster_id)

aws emr describe-cluster --cluster-id $CLUSTER_ID \
    --query 'Cluster.{Name:Name,State:Status.State,Master:MasterPublicDnsName}'
```

### Status dos steps

```bash
aws emr list-steps --cluster-id $CLUSTER_ID \
    --query 'Steps[].{Name:Name,State:Status.State}' \
    --output table
```

**Resultado esperado (apos conclusao):**

```
|              Name              |   State    |
+--------------------------------+------------+
|  Show-Results                  |  COMPLETED |
|  Copy-HDFS-results-to-S3       |  COMPLETED |
|  Hive-HDFS-Tables              |  COMPLETED |
|  Copy-data-to-HDFS             |  COMPLETED |
|  Hive-S3-Tables                |  COMPLETED |
```

### Logs de um step especifico

```bash
# Pegar o ID do primeiro step (Hive-S3-Tables)
STEP_ID=$(aws emr list-steps --cluster-id $CLUSTER_ID \
    --query 'Steps[-1].Id' --output text)

# Ver detalhes do step
aws emr describe-step --cluster-id $CLUSTER_ID --step-id $STEP_ID \
    --query 'Step.{Name:Name,State:Status.State,Message:Status.FailureDetails.Message}'
```

### Via Console AWS

1. Acesse: https://console.aws.amazon.com/elasticmapreduce/
2. Clique no cluster "hive-emr-cluster"
3. Aba "Steps" para ver o progresso
4. Aba "Hardware" para ver as instancias

---

## 13. Passo 6 — Workflow S3: Entendendo o que aconteceu

### O que e o workflow S3?

No workflow S3, os dados **permanecem no S3** o tempo todo. O Hive cria **tabelas externas** que apontam para os arquivos CSV no bucket. Quando voce faz uma query, o Hive le os dados diretamente do S3.

### Vantagens do workflow S3

- **Persistencia**: Dados continuam existindo mesmo depois de destruir o cluster
- **Compartilhamento**: Varios clusters podem ler os mesmos dados
- **Custo zero de armazenamento**: S3 e muito barato comparado a instancias EC2

### O script HQL que foi executado (setup-s3.hql)

Vamos entender cada parte. O script completo:

```sql
-- 1. Criar tabela externa para clientes
CREATE EXTERNAL TABLE IF NOT EXISTS clientes_s3 (
  id_cliente INT,
  nome STRING,
  email STRING,
  cidade STRING,
  estado STRING
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION 's3://BUCKET/data/s3/clientes/'
TBLPROPERTIES ("skip.header.line.count"="1");
```

| Comando | Explicacao |
|---|---|
| `CREATE EXTERNAL TABLE` | Cria uma tabela que aponta para dados existentes em algum lugar (S3, HDFS). Se voce deletar a tabela, os dados NAO sao apagados. |
| `IF NOT EXISTS` | So cria se a tabela nao existir. Permite rodar o script varias vezes sem erro. |
| `ROW FORMAT DELIMITED` | Diz que os dados sao delimitados por um caractere especifico. |
| `FIELDS TERMINATED BY ','` | O delimitador das colunas e a virgula (CSV). |
| `STORED AS TEXTFILE` | O arquivo esta em formato texto simples (nao binario). |
| `LOCATION 's3://...'` | Onde os dados estao fisicamente. No workflow S3, e no bucket. |
| `TBLPROPERTIES` | Configuracoes extras. Aqui pulamos a primeira linha (cabecalho do CSV). |

```sql
-- 2. Criar tabela de resultado (tambem no S3)
CREATE EXTERNAL TABLE IF NOT EXISTS resultado_vendas_s3 (
  estado STRING,
  categoria STRING,
  total_vendido DOUBLE,
  num_vendas INT
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION 's3://BUCKET/results/s3/';
```

Esta tabela vai receber o resultado da query. Quando fizermos INSERT OVERWRITE, o Hive vai escrever um arquivo CSV nessa localizacao.

```sql
-- 3. Query com JOIN e INSERT do resultado
INSERT OVERWRITE TABLE resultado_vendas_s3
SELECT c.estado, p.categoria,
       round(SUM(v.quantidade * p.preco), 2) AS total_vendido,
       COUNT(*) AS num_vendas
FROM vendas_s3 v
JOIN clientes_s3 c ON v.id_cliente = c.id_cliente
JOIN produtos_s3 p ON v.id_produto = p.id_produto
GROUP BY c.estado, p.categoria
ORDER BY total_vendido DESC;
```

| Parte | Explicacao |
|---|---|
| `INSERT OVERWRITE TABLE` | Escreve o resultado na tabela de destino. OVERWRITE substitui dados anteriores. |
| `JOIN ... ON ...` | Junta vendas com clientes pelo id_cliente, e com produtos pelo id_produto. |
| `SUM(v.quantidade * p.preco)` | Calcula o valor total de cada venda (quantidade x preco) e soma tudo. |
| `GROUP BY c.estado, p.categoria` | Agrupa os resultados por estado e categoria. |
| `ORDER BY total_vendido DESC` | Ordena do maior valor para o menor. |

### Como o Hive executa isso internamente?

O Hive converte essa query SQL em **jobs MapReduce**:

1. **Map**: Le cada linha das 3 tabelas, faz o JOIN, emite (estado+categoria, valor)
2. **Shuffle**: Agrupa por estado e categoria
3. **Reduce**: Soma os valores de cada grupo
4. **Output**: Escreve o arquivo CSV em `s3://BUCKET/results/s3/000000_0`

---

## 14. Passo 7 — Workflow HDFS: Entendendo o que aconteceu

### O que e o workflow HDFS?

No workflow HDFS, os dados sao **copiados do S3 para o HDFS** primeiro (via s3-dist-cp). Depois o Hive cria tabelas que apontam para os arquivos no HDFS. Ao final, o resultado e copiado de volta para o S3 para persistencia.

### Por que fazer isso?

- **Performance**: HDFS e mais rapido que S3 para leituras intensivas (dados locais vs rede)
- **Treinamento**: Entender como o HDFS funciona e importante para administradores Hadoop
- **Dados temporarios**: Dados intermediarios que nao precisam persistir

### O fluxo completo do HDFS

```
1. s3-dist-cp copia: S3 -> HDFS
   s3://BUCKET/data/hdfs/clientes/  -> hdfs:///data/hdfs/clientes/
   s3://BUCKET/data/hdfs/produtos/  -> hdfs:///data/hdfs/produtos/
   s3://BUCKET/data/hdfs/vendas/    -> hdfs:///data/hdfs/vendas/

2. Hive cria tabelas apontando para HDFS
   clientes_hdfs -> hdfs:///data/hdfs/clientes/
   produtos_hdfs -> hdfs:///data/hdfs/produtos/
   vendas_hdfs   -> hdfs:///data/hdfs/vendas/

3. INSERT OVERWRITE escreve resultado no HDFS
   resultado_vendas_hdfs -> hdfs:///data/hdfs/output/000000_0

4. s3-dist-cp copia: HDFS -> S3 (para persistir)
   hdfs:///data/hdfs/output/ -> s3://BUCKET/results/hdfs/
```

### O script HQL do HDFS (setup-hdfs.hql)

A diferenca principal e a localizacao:

```sql
CREATE EXTERNAL TABLE IF NOT EXISTS clientes_hdfs (...)
LOCATION 'hdfs:///data/hdfs/clientes/'
TBLPROPERTIES ("skip.header.line.count"="1");
```

Em vez de `s3://BUCKET/...`, usamos `hdfs:///data/hdfs/...`.

> **Nota**: O HDFS usa o protocolo `hdfs://`. O `/data/hdfs/` e o diretorio dentro do HDFS (nao confundir com o disco local do EC2).

### s3-dist-cp

`s3-dist-cp` e uma ferramenta otimizada do EMR para copiar dados entre S3 e HDFS. E similar ao `aws s3 cp`, mas muito mais rapida porque usa multiplas threads em paralelo.

```bash
# Copiar do S3 para HDFS
s3-dist-cp --src s3://BUCKET/data/hdfs/ --dest hdfs:///data/hdfs/

# Copiar do HDFS para S3
s3-dist-cp --src hdfs:///data/hdfs/output/ --dest s3://BUCKET/results/hdfs/
```

---

## 15. Passo 8 — Ver os Resultados

### Resultados do workflow S3

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="${ACCOUNT_ID}-emr-lab-hive"

echo "=== Resultados do workflow S3 ==="
aws s3 ls s3://${BUCKET}/results/s3/
```

**Resultado esperado:**

```
2026-05-21 ...          0  _SUCCESS
2026-05-21 ...        576  000000_0-hadoop_20260521...
```

O Hive gera um arquivo CSV com nome no formato `000000_0-hadoop_<timestamp>_<uuid>-1`. Para ver o conteudo, use `sync` com um diretorio temporario:

```bash
echo "=== Conteudo (formatado como tabela) ==="
aws s3 sync s3://${BUCKET}/results/s3/ /tmp/results-s3/ > /dev/null 2>&1
cat /tmp/results-s3/000000_0* | column -t -s','
rm -rf /tmp/results-s3/
```

**Resultado esperado (exemplo):**

```
SP            Eletronicos   9500.0   2
PA            Eletronicos   4500.0   1
BA            Eletronicos   4500.0   1
PR            Eletronicos   3200.0   2
RJ            Eletronicos   2500.0   1
DF            Eletronicos   2500.0   1
MG            Livros        600.0    1
...
```

### Resultados do workflow HDFS (copiados para S3)

```bash
echo "=== Resultados do workflow HDFS ==="
aws s3 ls s3://${BUCKET}/results/hdfs/
aws s3 cp s3://${BUCKET}/results/hdfs/000000_0 - | column -t -s','
```

Os resultados devem ser **identicos** ao S3 (e a mesma query).

### Diferenca entre os dois:

```bash
aws s3 sync s3://${BUCKET}/results/s3/ /tmp/compare-s3/ > /dev/null 2>&1
aws s3 cp s3://${BUCKET}/results/hdfs/000000_0 /tmp/compare-hdfs/ > /dev/null 2>&1
diff /tmp/compare-s3/000000_0* /tmp/compare-hdfs/000000_0
rm -rf /tmp/compare-s3 /tmp/compare-hdfs
```

Se nao houver diferenca, os dois workflows produziram o mesmo resultado. Parabens!

### Baixar tudo para a maquina local

```bash
mkdir -p results
aws s3 sync s3://${BUCKET}/results/ results/
ls -la results/
```

---

## 16. Passo 9 — Acessar o cluster via SSH e explorar

> **Guia completo de SSH**: [SSH.md](SSH.md) — instrucoes detalhadas, troubleshooting, e localizacao da chave PEM.
>
> A chave privada `labsuser.pem` esta em `tutoriais/aws_credenciais/labsuser.pem`.

### Obter o DNS do master

```bash
CLUSTER_ID=$(terraform output -raw cluster_id)
MASTER_DNS=$(aws emr describe-cluster --cluster-id $CLUSTER_ID \
    --query 'Cluster.MasterPublicDnsName' --output text)
echo "Master DNS: $MASTER_DNS"
```

### Conectar via SSH

#### Dentro do Learner Lab

O Learner Lab fornece um terminal no navegador (painel esquerdo da interface do lab, ou AWS CloudShell). Esse terminal **ja esta na mesma rede** do cluster EMR e possui a chave `vockey` pre-instalada em `~/.ssh/labsuser.pem`.

Passo a passo:
1. No painel do Learner Lab, clique em **"AWS Details"** e em **"Download PEM"** (macOS/Linux) ou **"Download PPK"** (Windows)
2. Se estiver usando o terminal embutido do lab, a chave ja existe em `~/.ssh/labsuser.pem`
3. Execute:

```bash
ssh -i ~/.ssh/labsuser.pem -o StrictHostKeyChecking=no hadoop@$MASTER_DNS
```

#### Fora do Learner Lab (conta AWS propria)

Em uma conta AWS propria (nao Learner Lab), o SSH funciona normalmente. O cluster ja tem a chave `vockey` associada no `main.tf`. Porem, o security group do master node precisa permitir SSH na porta 22 do seu IP.

**Verificar e liberar o security group:**

```bash
# Descobrir o security group do master node
SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=ElasticMapReduce-Master-Public*" \
    --query 'SecurityGroups[0].GroupId' --output text)
echo "Security Group: $SG_ID"

# Adicionar regra SSH (substitua pelo seu IP ou use 0.0.0.0/0)
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp --port 22 \
    --cidr $(curl -s ifconfig.me)/32
```

Depois de liberado:

```bash
ssh -i ~/Documents/Big\ Data/tutoriais/aws_credenciais/labsuser.pem \
    -o StrictHostKeyChecking=no hadoop@$MASTER_DNS
```

### Explorar as tabelas Hive

```bash
# Listar tabelas
hive -e 'SHOW TABLES;'
```

**Resultado esperado:**

```
clientes_hdfs
clientes_s3
produtos_hdfs
produtos_s3
resultado_vendas_hdfs
resultado_vendas_s3
vendas_hdfs
vendas_s3
```

```bash
# Ver schema de uma tabela
hive -e 'DESCRIBE clientes_s3;'
```

```bash
# Ver amostra dos dados
hive -e 'SELECT * FROM clientes_s3 LIMIT 5;'
```

```bash
# Contar registros
hive -e 'SELECT COUNT(*) FROM vendas_s3;'
```

### Ver resultados pelo Hive

```bash
# Resultado S3
echo "=== Workflow S3 ==="
hive -e 'SELECT * FROM resultado_vendas_s3;'

# Resultado HDFS
echo "=== Workflow HDFS ==="
hive -e 'SELECT * FROM resultado_vendas_hdfs;'
```

### Explorar o HDFS

```bash
# Diretorios de dados
hdfs dfs -ls /data/hdfs/

# Dados de entrada no HDFS (copiados do S3)
hdfs dfs -ls /data/hdfs/clientes/
hdfs dfs -cat /data/hdfs/clientes/clientes.csv | head -3

# Resultados no HDFS
hdfs dfs -ls /data/hdfs/output/
hdfs dfs -cat /data/hdfs/output/000000_0
```

### Ver os processos rodando

```bash
jps
```

**Resultado esperado:**

```
XXXX NameNode
XXXX DataNode
XXXX ResourceManager
XXXX NodeManager
XXXX HiveMetaStore
XXXX HiveServer2
XXXX Jps
```

### Rodar queries manualmente (experimente!)

Dentro do SSH, voce pode rodar queries Hive adicionais:

```bash
# Query 1: Cliente que mais comprou
hive -e "
  SELECT c.nome, SUM(v.quantidade * p.preco) AS total_gasto
  FROM vendas_s3 v
  JOIN clientes_s3 c ON v.id_cliente = c.id_cliente
  JOIN produtos_s3 p ON v.id_produto = p.id_produto
  GROUP BY c.nome
  ORDER BY total_gasto DESC
  LIMIT 5;
"

# Query 2: Produto mais vendido em quantidade
hive -e "
  SELECT p.nome_produto, SUM(v.quantidade) AS total_unidades
  FROM vendas_s3 v
  JOIN produtos_s3 p ON v.id_produto = p.id_produto
  GROUP BY p.nome_produto
  ORDER BY total_unidades DESC
  LIMIT 5;
"

# Query 3: Vendas por estado
hive -e "
  SELECT c.estado, COUNT(*) AS total_vendas
  FROM vendas_s3 v
  JOIN clientes_s3 c ON v.id_cliente = c.id_cliente
  GROUP BY c.estado
  ORDER BY total_vendas DESC;
"
```

### Sair do SSH

```bash
exit
```

---

## 17. Passo 10 — Descomissionamento

> **IMPORTANTE**: Sempre destrua os recursos ao terminar. Cada hora que o cluster fica rodando custa ~$0.20.

### Via script automatizado (recomendado)

```bash
cd ~/Documents/Big\ Data/tutoriais/aws-emr-hive-tutorial
./scripts/destroy.sh
```

### Via Terraform

```bash
cd ~/Documents/Big\ Data/tutoriais/aws-emr-hive-tutorial/terraform
terraform destroy -auto-approve
```

### Manualmente (caso o Terraform falhe)

```bash
# 1. Encerrar cluster EMR
CLUSTER_ID=$(aws emr list-clusters --cluster-states WAITING \
    --query 'Clusters[0].Id' --output text)
aws emr terminate-clusters --cluster-ids $CLUSTER_ID

# 2. Aguardar terminio (opcional)
aws emr describe-cluster --cluster-id $CLUSTER_ID \
    --query 'Cluster.Status.State'

# 3. Esvaziar e remover bucket S3
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3 rm s3://${ACCOUNT_ID}-emr-lab-hive --recursive
aws s3 rb s3://${ACCOUNT_ID}-emr-lab-hive
```

### Verificar que tudo foi removido

```bash
# Nenhum cluster ativo
aws emr list-clusters --cluster-states STARTING BOOTSTRAPPING RUNNING WAITING

# Nenhum bucket com nosso nome
aws s3 ls | grep emr-lab-hive
```

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
2. **Resultados salvos no S3** — nao precisa manter o cluster para ver resultados
3. **Sem custo de armazenamento** — o bucket S3 custa centavos por mes
4. **Planeje sua sessao** — descubra o que vai fazer antes de subir o cluster

---

## 19. Troubleshooting

| Problema | Causa | Solucao |
|---|---|---|
| `terraform init` falha | Provider AWS nao baixa | Verifique conexao com internet |
| `terraform apply` erro "role" | Roles EMR nao existem | Sao pre-criadas no Learner Lab. Se faltarem, contate o instrutor |
| Cluster fica em STARTING >15min | Provisionamento lento | Verifique logs no console AWS. Pode ser limite de orcamento |
| Step FAILED | Script HQL ou dados nao encontrados | Verifique logs do step: `aws emr describe-step` |
| Hive table not found | Step anterior falhou | Steps sao sequenciais. Resolva o step que falhou primeiro |
| `s3://BUCKET/hive/...` nao encontrado | Upload dos HQL falhou | Verifique: `aws s3 ls s3://BUCKET/hive/` |
| `000000_0` vazio | INSERT não gerou dados | Verifique se as tabelas tem dados: `hive -e 'SELECT COUNT(*) FROM clientes_s3'` |
| Key pair vockey nao encontrado | Key pair nao existe na regiao | Crie uma key pair ou use outra e altere `main.tf` |
| Instance limit exceeded | Mais de 9 instancias rodando | Encerre recursos nao utilizados |
| Orcamento esgotado | Budget do lab excedido | Nao ha recuperacao. Monitore o budget |
| Cluster termina sozinho | Sessao do lab expirou | Resultados no S3 persistem. Recrie o cluster na proxima sessao |
| `hadoop fs -cat s3://...` falha | Permissao S3 | O EMR tem a role EMR_EC2_DefaultRole que da acesso ao S3. Se falhar, verifique as permissoes |

---

## Anexo: Consultas Hive Uteis

```sql
-- Listar todas as tabelas
SHOW TABLES;

-- Descrever estrutura de uma tabela
DESCRIBE clientes_s3;

-- Ver formato detalhado (com propriedades)
DESCRIBE FORMATTED clientes_s3;

-- Ver localizacao dos dados
DESCRIBE FORMATTED clientes_s3;
-- Procure pela linha "Location:"

-- Amostra de dados
SELECT * FROM clientes_s3 LIMIT 10;

-- Contar registros
SELECT COUNT(*) FROM vendas_s3;
SELECT estado, COUNT(*) FROM clientes_s3 GROUP BY estado;

-- Estatisticas basicas
DESCRIBE resultado_vendas_s3;
SELECT SUM(total_vendido) AS receita_total FROM resultado_vendas_s3;
SELECT COUNT(*) AS total_linhas FROM resultado_vendas_s3;
SELECT AVG(total_vendido) AS media_por_grupo FROM resultado_vendas_s3;
```
