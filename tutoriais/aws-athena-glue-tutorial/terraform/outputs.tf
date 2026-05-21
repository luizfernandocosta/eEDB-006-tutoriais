output "s3_bucket" {
  description = "S3 bucket name for Athena data storage"
  value       = local.bucket_name
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.athena_lab.arn
}

output "s3_data_path" {
  description = "S3 path for input data"
  value       = "s3://${local.bucket_name}/data/"
}

output "s3_results_path" {
  description = "S3 path for query results"
  value       = "s3://${local.bucket_name}/results/resultado_vendas/"
}

output "athena_work_group" {
  description = "Athena work group"
  value       = "primary"
}

output "glue_database" {
  description = "Glue database name"
  value       = "athena_lab"
}