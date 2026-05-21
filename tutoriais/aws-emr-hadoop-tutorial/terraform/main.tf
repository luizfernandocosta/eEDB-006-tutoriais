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
  bucket_name = "${data.aws_caller_identity.current.account_id}-emr-lab-wordcount"
}

# ---------------------------------------------------------------------------
# S3 BUCKET
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "emr_lab" {
  bucket        = local.bucket_name
  force_destroy = true

  tags = {
    Name      = local.bucket_name
    Project   = "emr-wordcount-lab"
    ManagedBy = "terraform"
  }
}

# ---------------------------------------------------------------------------
# DADOS DE ENTRADA
# ---------------------------------------------------------------------------

resource "aws_s3_object" "input_data" {
  for_each = fileset("${path.module}/../data", "**")

  bucket = aws_s3_bucket.emr_lab.id
  key    = "input/${each.value}"
  source = "${path.module}/../data/${each.value}"
  etag   = filemd5("${path.module}/../data/${each.value}")
}

# ---------------------------------------------------------------------------
# FONTES JAVA (para compilacao no cluster)
# ---------------------------------------------------------------------------

resource "aws_s3_object" "java_sources" {
  for_each = fileset("${path.module}/../src", "**")

  bucket = aws_s3_bucket.emr_lab.id
  key    = "src/${each.value}"
  source = "${path.module}/../src/${each.value}"
  etag   = filemd5("${path.module}/../src/${each.value}")
}

# ---------------------------------------------------------------------------
# BOOTSTRAP
# ---------------------------------------------------------------------------

resource "aws_s3_object" "bootstrap_script" {
  bucket = aws_s3_bucket.emr_lab.id
  key    = "scripts/bootstrap.sh"
  content = <<-SCRIPT
    #!/bin/bash
    echo "Bootstrap complete."
  SCRIPT
}

# ---------------------------------------------------------------------------
# CLUSTER EMR
# ---------------------------------------------------------------------------

resource "aws_emr_cluster" "wordcount" {
  name          = "wordcount-emr-cluster"
  release_label = "emr-6.15.0"
  applications  = ["Hadoop"]

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
  # Step 1: Compilar Java no cluster (usa javac + hadoop classpath do EMR)
  # -----------------------------------------------------------------------
  step {
    name              = "Compile-WordCount-JAR"
    action_on_failure = "TERMINATE_CLUSTER"

    hadoop_jar_step {
      jar  = "command-runner.jar"
      args = [
        "bash", "-c",
        "set -e; HCP=$(hadoop classpath); mkdir -p /home/hadoop/wc-build; aws s3 cp s3://${local.bucket_name}/src/ /home/hadoop/wc-build/ --recursive; javac -classpath \"$HCP\" -d /home/hadoop/wc-build /home/hadoop/wc-build/*.java; cd /home/hadoop/wc-build && jar cf wordcount.jar *.class; aws s3 cp wordcount.jar s3://${local.bucket_name}/jars/wordcount.jar; echo COMPILE_OK"
      ]
    }
  }

  # -----------------------------------------------------------------------
  # Step 2: Copiar dados do S3 para HDFS
  # -----------------------------------------------------------------------
  step {
    name              = "Copy-input-to-HDFS"
    action_on_failure = "CONTINUE"

    hadoop_jar_step {
      jar  = "command-runner.jar"
      args = ["s3-dist-cp", "--src", "s3://${local.bucket_name}/input/", "--dest", "hdfs:///input/"]
    }
  }

  # -----------------------------------------------------------------------
  # Step 3: Executar WordCount MapReduce (command-runner para resolver args)
  # -----------------------------------------------------------------------
  step {
    name              = "Run-WordCount-MapReduce"
    action_on_failure = "CONTINUE"

    hadoop_jar_step {
      jar  = "command-runner.jar"
      args = ["hadoop", "jar", "s3://${local.bucket_name}/jars/wordcount.jar", "WordCountApplication", "hdfs:///input/", "hdfs:///output/wordcount/"]
    }
  }

  # -----------------------------------------------------------------------
  # Step 4: Copiar resultados do HDFS para S3
  # -----------------------------------------------------------------------
  step {
    name              = "Copy-output-to-S3"
    action_on_failure = "CONTINUE"

    hadoop_jar_step {
      jar  = "command-runner.jar"
      args = ["s3-dist-cp", "--src", "hdfs:///output/wordcount/", "--dest", "s3://${local.bucket_name}/output/"]
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
      args = [
        "bash", "-c",
        "echo '=== WordCount Results ==='; hdfs dfs -cat /output/wordcount/part-r-00000 2>/dev/null | sort -t$'\\t' -k2 -nr | head -20; echo '=== Total words ==='; hdfs dfs -cat /output/wordcount/part-r-00000 2>/dev/null | wc -l; echo '=== S3 Output ==='; aws s3 ls s3://${local.bucket_name}/output/"
      ]
    }
  }

  tags = {
    Project   = "emr-wordcount-lab"
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

# ---------------------------------------------------------------------------
# OUTPUTS
# ---------------------------------------------------------------------------

output "cluster_id" {
  value = aws_emr_cluster.wordcount.id
}

output "cluster_master_public_dns" {
  value = aws_emr_cluster.wordcount.master_public_dns
}

output "s3_bucket" {
  value = aws_s3_bucket.emr_lab.id
}

output "s3_output_path" {
  value = "s3://${aws_s3_bucket.emr_lab.id}/output/"
}
