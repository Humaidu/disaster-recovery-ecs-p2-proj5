# Prefix for ALB resource names
variable "name" {
  description = "ALB name prefix"
  type        = string
}

# ID of the VPC where ALB will be deployed
variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

# List of public subnet IDs for ALB deployment
variable "public_subnets" {
  description = "List of public subnet IDs"
  type        = list(string)
}

# Common tags for all resources
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
