output "read_replica_endpoint" {
  value = aws_db_instance.replica.endpoint
}

output "read_replica_arn" {
  value = aws_db_instance.replica.arn
}

output "read_replica_identifier" {
  value = aws_db_instance.replica.identifier
}

