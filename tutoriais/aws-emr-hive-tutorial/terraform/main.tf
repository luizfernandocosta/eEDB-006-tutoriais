data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

locals {
  bucket_name = "${data.aws_caller_identity.current.account_id}-emr-lab-hive"

  show_results_cmd = <<-SCRIPT
    echo ''
    echo '========================================'
    echo '  RESULTADOS - S3'
    echo '========================================'
    echo ''
    echo '--- Conteudo da tabela resultado_vendas_s3 ---'
    hive -S -e 'SELECT * FROM resultado_vendas_s3;'
    echo ''
    echo '--- Arquivos no S3 ---'
    aws s3 ls s3://${local.bucket_name}/results/s3/
    echo ''
    echo '========================================'
    echo '  RESULTADOS - HDFS'
    echo '========================================'
    echo ''
    echo '--- Conteudo da tabela resultado_vendas_hdfs ---'
    hive -S -e 'SELECT * FROM resultado_vendas_hdfs;'
    echo ''
    echo '--- Arquivos no HDFS ---'
    hdfs dfs -ls /data/hdfs/output/
  SCRIPT
}

# ---------------------------------------------------------------------------
# S3 BUCKET
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "emr_lab" {
  bucket        = local.bucket_name
  force_destroy = true

  tags = {
    Name      = local.bucket_name
    Project   = "emr-hive-lab"
    ManagedBy = "terraform"
  }
}

# ---------------------------------------------------------------------------
# DADOS CSV - Workflow S3 (lidos diretamente pelo Hive no S3)
# ---------------------------------------------------------------------------

resource "aws_s3_object" "clientes_s3" {
  bucket = aws_s3_bucket.emr_lab.id
  key    = "data/s3/clientes/clientes.csv"
  source = "${path.module}/../data/clientes.csv"
  etag   = filemd5("${path.module}/../data/clientes.csv")
}

resource "aws_s3_object" "produtos_s3" {
  bucket = aws_s3_bucket.emr_lab.id
  key    = "data/s3/produtos/produtos.csv"
  source = "${path.module}/../data/produtos.csv"
  etag   = filemd5("${path.module}/../data/produtos.csv")
}

resource "aws_s3_object" "vendas_s3" {
  bucket = aws_s3_bucket.emr_lab.id
  key    = "data/s3/vendas/vendas.csv"
  source = "${path.module}/../data/vendas.csv"
  etag   = filemd5("${path.module}/../data/vendas.csv")
}

# ---------------------------------------------------------------------------
# DADOS CSV - Workflow HDFS (copiados do S3 para o HDFS via s3-dist-cp)
# ---------------------------------------------------------------------------

resource "aws_s3_object" "clientes_hdfs" {
  bucket = aws_s3_bucket.emr_lab.id
  key    = "data/hdfs/clientes/clientes.csv"
  source = "${path.module}/../data/clientes.csv"
  etag   = filemd5("${path.module}/../data/clientes.csv")
}

resource "aws_s3_object" "produtos_hdfs" {
  bucket = aws_s3_bucket.emr_lab.id
  key    = "data/hdfs/produtos/produtos.csv"
  source = "${path.module}/../data/produtos.csv"
  etag   = filemd5("${path.module}/../data/produtos.csv")
}

resource "aws_s3_object" "vendas_hdfs" {
  bucket = aws_s3_bucket.emr_lab.id
  key    = "data/hdfs/vendas/vendas.csv"
  source = "${path.module}/../data/vendas.csv"
  etag   = filemd5("${path.module}/../data/vendas.csv")
}

# ---------------------------------------------------------------------------
# SCRIPTS HQL (Hive) - armazenados no S3 para execucao via EMR Steps
# ---------------------------------------------------------------------------

resource "aws_s3_object" "bootstrap_script" {
  bucket  = aws_s3_bucket.emr_lab.id
  key     = "scripts/bootstrap.sh"
  content = <<-SCRIPT
    #!/bin/bash
    echo "Bootstrap: Configuring environment..."
    # HDFS directories will be created automatically by s3-dist-cp and Hive steps
    echo "Bootstrap complete."
  SCRIPT
}

resource "aws_s3_object" "hive_s3_hql" {
  bucket  = aws_s3_bucket.emr_lab.id
  key     = "hive/setup-s3.hql"
  content = <<-HQL
    -- ============================================================
    -- WORKFLOW S3: Tabelas externas sobre dados no S3
    -- ============================================================

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
    LOCATION 's3://${local.bucket_name}/data/s3/clientes/'
    TBLPROPERTIES ("skip.header.line.count"="1");

    CREATE EXTERNAL TABLE IF NOT EXISTS produtos_s3 (
      id_produto INT,
      nome_produto STRING,
      categoria STRING,
      preco DOUBLE
    )
    ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ','
    STORED AS TEXTFILE
    LOCATION 's3://${local.bucket_name}/data/s3/produtos/'
    TBLPROPERTIES ("skip.header.line.count"="1");

    CREATE EXTERNAL TABLE IF NOT EXISTS vendas_s3 (
      id_venda INT,
      id_cliente INT,
      id_produto INT,
      quantidade INT,
      data_venda STRING
    )
    ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ','
    STORED AS TEXTFILE
    LOCATION 's3://${local.bucket_name}/data/s3/vendas/'
    TBLPROPERTIES ("skip.header.line.count"="1");

    -- Tabela de resultado no S3 (o CSV sera gerado aqui)
    CREATE EXTERNAL TABLE IF NOT EXISTS resultado_vendas_s3 (
      estado STRING,
      categoria STRING,
      total_vendido DOUBLE,
      num_vendas INT
    )
    ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ','
    STORED AS TEXTFILE
    LOCATION 's3://${local.bucket_name}/results/s3/';

    -- Query com JOIN e agregacao
    INSERT OVERWRITE TABLE resultado_vendas_s3
    SELECT c.estado, p.categoria,
           round(SUM(v.quantidade * p.preco), 2) AS total_vendido,
           COUNT(*) AS num_vendas
    FROM vendas_s3 v
    JOIN clientes_s3 c ON v.id_cliente = c.id_cliente
    JOIN produtos_s3 p ON v.id_produto = p.id_produto
    GROUP BY c.estado, p.categoria
    ORDER BY total_vendido DESC;
  HQL
}

resource "aws_s3_object" "hive_hdfs_hql" {
  bucket  = aws_s3_bucket.emr_lab.id
  key     = "hive/setup-hdfs.hql"
  content = <<-HQL
    -- ============================================================
    -- WORKFLOW HDFS: Tabelas externas sobre dados no HDFS
    -- Os CSVs foram copiados do S3 para HDFS via s3-dist-cp
    -- ============================================================

    CREATE EXTERNAL TABLE IF NOT EXISTS clientes_hdfs (
      id_cliente INT,
      nome STRING,
      email STRING,
      cidade STRING,
      estado STRING
    )
    ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ','
    STORED AS TEXTFILE
    LOCATION 'hdfs:///data/hdfs/clientes/'
    TBLPROPERTIES ("skip.header.line.count"="1");

    CREATE EXTERNAL TABLE IF NOT EXISTS produtos_hdfs (
      id_produto INT,
      nome_produto STRING,
      categoria STRING,
      preco DOUBLE
    )
    ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ','
    STORED AS TEXTFILE
    LOCATION 'hdfs:///data/hdfs/produtos/'
    TBLPROPERTIES ("skip.header.line.count"="1");

    CREATE EXTERNAL TABLE IF NOT EXISTS vendas_hdfs (
      id_venda INT,
      id_cliente INT,
      id_produto INT,
      quantidade INT,
      data_venda STRING
    )
    ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ','
    STORED AS TEXTFILE
    LOCATION 'hdfs:///data/hdfs/vendas/'
    TBLPROPERTIES ("skip.header.line.count"="1");

    -- Tabela de resultado no HDFS (o CSV sera gerado aqui)
    -- Usamos uma tabela gerenciada que escreve no HDFS
    CREATE TABLE IF NOT EXISTS resultado_vendas_hdfs (
      estado STRING,
      categoria STRING,
      total_vendido DOUBLE,
      num_vendas INT
    )
    ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ','
    STORED AS TEXTFILE
    LOCATION 'hdfs:///data/hdfs/output/';

    -- Mesma query, mesma logica, dados no HDFS
    INSERT OVERWRITE TABLE resultado_vendas_hdfs
    SELECT c.estado, p.categoria,
           round(SUM(v.quantidade * p.preco), 2) AS total_vendido,
           COUNT(*) AS num_vendas
    FROM vendas_hdfs v
    JOIN clientes_hdfs c ON v.id_cliente = c.id_cliente
    JOIN produtos_hdfs p ON v.id_produto = p.id_produto
    GROUP BY c.estado, p.categoria
    ORDER BY total_vendido DESC;
  HQL
}

# ---------------------------------------------------------------------------
# CLUSTER EMR com Hive
# ---------------------------------------------------------------------------

resource "aws_emr_cluster" "hive_lab" {
  name          = "hive-emr-cluster"
  release_label = "emr-6.15.0"
  applications  = ["Hadoop", "Hive"]

  service_role = "EMR_DefaultRole"

  ec2_attributes {
    key_name                          = "vockey"
    instance_profile                  = "EMR_EC2_DefaultRole"
    subnet_id                         = data.aws_subnets.public.ids[0]
    additional_master_security_groups = ""
    additional_slave_security_groups  = ""
  }

  master_instance_group {
    instance_type  = "m4.large"
    instance_count = 1
  }

  core_instance_group {
    instance_type  = "m4.large"
    instance_count = 1
  }

  bootstrap_action {
    path = "s3://${aws_s3_bucket.emr_lab.id}/scripts/bootstrap.sh"
    name = "setup-hdfs-dirs"
  }

  # -----------------------------------------------------------------------
  # Step 1: Workflow S3 - tabelas externas, query, INSERT no S3
  # -----------------------------------------------------------------------
  step {
    name              = "Hive-S3-Tables"
    action_on_failure = "CONTINUE"

    hadoop_jar_step {
      jar  = "command-runner.jar"
      args = ["hive", "-f", "s3://${aws_s3_bucket.emr_lab.id}/hive/setup-s3.hql"]
    }
  }

  # -----------------------------------------------------------------------
  # Step 2: Copiar dados do S3 para HDFS (para o workflow HDFS)
  # -----------------------------------------------------------------------
  step {
    name              = "Copy-data-to-HDFS"
    action_on_failure = "CONTINUE"

    hadoop_jar_step {
      jar  = "command-runner.jar"
      args = ["s3-dist-cp", "--src", "s3://${aws_s3_bucket.emr_lab.id}/data/hdfs/", "--dest", "hdfs:///data/hdfs/"]
    }
  }

  # -----------------------------------------------------------------------
  # Step 3: Workflow HDFS - tabelas, query, INSERT no HDFS
  # -----------------------------------------------------------------------
  step {
    name              = "Hive-HDFS-Tables"
    action_on_failure = "CONTINUE"

    hadoop_jar_step {
      jar  = "command-runner.jar"
      args = ["hive", "-f", "s3://${aws_s3_bucket.emr_lab.id}/hive/setup-hdfs.hql"]
    }
  }

  # -----------------------------------------------------------------------
  # Step 4: Copiar resultados do HDFS de volta para S3 (persistencia)
  # -----------------------------------------------------------------------
  step {
    name              = "Copy-HDFS-results-to-S3"
    action_on_failure = "CONTINUE"

    hadoop_jar_step {
      jar  = "command-runner.jar"
      args = ["s3-dist-cp", "--src", "hdfs:///data/hdfs/output/", "--dest", "s3://${aws_s3_bucket.emr_lab.id}/results/hdfs/"]
    }
  }

  # -----------------------------------------------------------------------
  # Step 5: Exibir resultados nos logs do step
  # -----------------------------------------------------------------------
  step {
    name              = "Show-Results"
    action_on_failure = "CONTINUE"

    hadoop_jar_step {
      jar  = "command-runner.jar"
      args = ["bash", "-c", local.show_results_cmd]
    }
  }

  tags = {
    Project   = "emr-hive-lab"
    ManagedBy = "terraform"
  }

  lifecycle {
    ignore_changes = [
      step,
      ec2_attributes[0].additional_master_security_groups,
      ec2_attributes[0].additional_slave_security_groups,
    ]
  }
}
