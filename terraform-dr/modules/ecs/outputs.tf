output "ecs_cluster_id" {
  value = aws_ecs_cluster.this.id
}

output "ecs_service_name" {
  value = aws_ecs_service.this.name
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.this.arn
}

output "ecs_sg_id" {
  description = "The ID of the ECS security group"
  value       = aws_security_group.ecs_sg.id
}