variable "region" {
  description = "The AWS region where the disaster recovery infrastructure will be deployed."
  default = "eu-central-1"
}

# ECS Variables
variable "cluster_name" {
  description = "The name of the ECS cluster to create in the DR region."
  default     = "lamp-dr-cluster"
}

variable "service_name" {
  description = "The name of the ECS Fargate service for the LAMP app in the DR region."
  default     = "lamp-dr-service"
}

variable "task_family" {
  description = "The ECS task definition family name."
  default = "lamp-dr-task"
}

variable "container_name" {
  description = "The name of the Docker container running the PHP application."
  default     = "lamp-stack-app"
}

variable "container_image" {
  description = "The full image path in ECR or DockerHub for the PHP container."
  default = "149536482038.dkr.ecr.eu-west-1.amazonaws.com/lamp-stack-app:latest"
}

variable "secret_arn" {
  description = "The ARN of the AWS Secrets Manager secret storing the DB credentials."
  default     = "arn:aws:secretsmanager:eu-central-1:149536482038:secret:lamp-db-credentials-yGOMu7"

}

# RDS Variables
variable "replica_identifier" {
  description = "The identifier to assign to the RDS read replica."
  default     = "lamp-dr-replica"
}

variable "source_db_arn" {
  description = "The identifier of the source RDS instance to replicate from."
  default = "arn:aws:rds:eu-west-1:149536482038:db:lampdb-ecs"
}

variable "db_instance_class" {
  description = "The instance class for the RDS read replica."
  default     = "db.t3.micro"
}
