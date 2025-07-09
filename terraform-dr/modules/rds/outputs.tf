output "read_replica_endpoint" {
  value = aws_db_instance.replica.endpoint
}

output "read_replica_arn" {
  value = aws_db_instance.replica.arn
}
