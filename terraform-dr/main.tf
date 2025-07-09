provider "aws" {
  alias  = "source"
  region = "eu-west-1"
}

provider "aws" {
  alias  = "dr"
  region = "eu-central-1"
}

# VPC setup
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  providers = {
    aws = aws.dr
  }

  name = "lamp-dr-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["eu-central-1a", "eu-central-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]

  enable_dns_hostnames = true
  enable_dns_support   = true

}

# ECS Disaster Recovery Cluster + Service
module "ecs_dr" {
  source            = "./modules/ecs"

  providers = {
    aws = aws.dr
  }

  cluster_name      = var.cluster_name
  service_name      = var.service_name
  task_family       = var.task_family
  container_name    = var.container_name
  container_image   = var.container_image
  secret_arn        = var.secret_arn
  region            = var.region
  public_subnets   = module.vpc.public_subnets
  vpc_id           = module.vpc.vpc_id

}

# RDS Read Replica in DR region
module "rds_dr" {
  source                = "./modules/rds"

  providers = {
    aws = aws.dr
  }

  replica_identifier    = var.replica_identifier
  source_db_arn  = var.source_db_arn
  instance_class        = var.db_instance_class
  private_subnets      = module.vpc.private_subnets
  vpc_id               = module.vpc.vpc_id
  ecs_sg_id            = module.ecs_dr.ecs_sg_id
  primary_kms_key_arn   = "arn:aws:kms:eu-west-1:149536482038:key/mrk-8bb92a8f9cb44411a1506bf4b3eac26e"

}

