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

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  bucket_name = "${local.account_id}-athena-lab"
}

resource "aws_s3_bucket" "athena_lab" {
  bucket        = local.bucket_name
  force_destroy = true
}

resource "aws_s3_object" "clientes" {
  bucket = aws_s3_bucket.athena_lab.id
  key    = "data/clientes/clientes.csv"
  source = "../data/clientes.csv"
  etag   = filemd5("../data/clientes.csv")
}

resource "aws_s3_object" "produtos" {
  bucket = aws_s3_bucket.athena_lab.id
  key    = "data/produtos/produtos.csv"
  source = "../data/produtos.csv"
  etag   = filemd5("../data/produtos.csv")
}

resource "aws_s3_object" "vendas" {
  bucket = aws_s3_bucket.athena_lab.id
  key    = "data/vendas/vendas.csv"
  source = "../data/vendas.csv"
  etag   = filemd5("../data/vendas.csv")
}

resource "aws_s3_object" "athena_results_folder" {
  bucket = aws_s3_bucket.athena_lab.id
  key    = "results/resultado_vendas/"
}

resource "aws_s3_object" "athena_query_results_folder" {
  bucket = aws_s3_bucket.athena_lab.id
  key    = "athena-query-results/"
}