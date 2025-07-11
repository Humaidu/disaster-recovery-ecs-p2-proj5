# ECS Outputs
output "ecs_cluster_id" {
  description = "ID of the ECS Cluster in DR region"
  value       = module.ecs_dr.ecs_cluster_id
}

output "ecs_service_name" {
  description = "Name of the ECS Service"
  value       = module.ecs_dr.ecs_service_name
}

output "task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = module.ecs_dr.task_definition_arn
}

# RDS Outputs
output "read_replica_endpoint" {
  description = "Endpoint of the RDS read replica"
  value       = module.rds_dr.read_replica_endpoint
}

output "read_replica_arn" {
  description = "ARN of the RDS read replica"
  value       = module.rds_dr.read_replica_arn
}

output "secret_arn" {
  value = module.ecs_dr.secret_arn
}

output "read_replica_identifier" {
  value = module.rds_dr.read_replica_identifier
}

