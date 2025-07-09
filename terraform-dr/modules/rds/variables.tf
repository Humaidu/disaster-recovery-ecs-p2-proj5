variable "replica_identifier" {
  description = "The identifier to assign to the RDS read replica."
}

variable "source_db_arn" {
  description = "The DB identifier of the source (primary) RDS instance to replicate from."
}

variable "instance_class" {
  description = "The instance type for the RDS read replica."
  default     = "db.t3.micro"
}

variable "vpc_id" {
  description = "VPC ID."
}

variable "private_subnets" {
  description = "List of subnet IDs for ECS task networking."
  type        = list(string)
}

variable "ecs_sg_id" {
  description = "The security group ID of the ECS service to allow DB traffic"
  type        = string
}

variable "primary_kms_key_arn" {
  description = "The ARN of the existing primary KMS key in eu-west-1"
  type        = string
}
