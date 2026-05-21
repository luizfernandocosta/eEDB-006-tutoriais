output "cluster_id" {
  value = aws_emr_cluster.hive_lab.id
}

output "master_dns" {
  value = aws_emr_cluster.hive_lab.master_public_dns
}

output "s3_bucket" {
  value = aws_s3_bucket.emr_lab.id
}

output "s3_results_path" {
  value = "s3://${aws_s3_bucket.emr_lab.id}/results/s3/"
}

output "hdfs_results_path" {
  value = "hdfs:///data/hdfs/output/"
}
