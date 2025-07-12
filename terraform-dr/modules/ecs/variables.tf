variable "cluster_name" {
  description = "The name of the ECS cluster."
}

variable "service_name" {
  description = "The name of the ECS Fargate service to run."
}

variable "task_family" {
  description = "The ECS task definition family name."
}

variable "container_name" {
  description = "The name of the container inside the ECS task."
}

variable "container_image" {
  description = "The container image to deploy, usually from ECR."
}

variable "secret_arn" {
  description = "The ARN of the AWS Secrets Manager secret used to inject DB credentials."
}

variable "region" {
  description = "The AWS region where the ECS resources are created."
}

variable "vpc_id" {
  description = "VPC ID."
}

variable "public_subnets" {
  description = "List of subnet IDs for ECS task networking."
  type        = list(string)
}

variable "private_subnets" {
  description = "List of subnet IDs for ECS task networking."
  type        = list(string)
}

variable "target_group_arn" {
  description = "Target group ARN for the ECS service to attach to"
  type        = string
}

variable "alb_sg_id" {
  description = "The security group ID of the ECS service to allow DB traffic"
  type        = string
}
