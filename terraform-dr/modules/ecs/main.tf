# Security Group for ECS tasks
resource "aws_security_group" "ecs_sg" {
  name        = "ecs-task-sg"
  vpc_id      = var.vpc_id
  description = "Allow HTTP out and DB in"
  
  # Allow HTTP traffic from anywhere (or restrict to your IP range)
  ingress {
    description = "Allow HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [var.alb_sg_id]
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# ECS Cluster
resource "aws_ecs_cluster" "this" {
  name = var.cluster_name
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution" {
  name = "ecsTaskExecutionRoleDR"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

# Attach Execution Policy
resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM Policy to access Secret Manager 
resource "aws_iam_policy" "ecs_secrets_access" {
  name        = "ecs-secrets-access-policy-dr"
  description = "Allow ECS DR task to read DB credentials secret"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue"
        ],
        Resource = [
          "arn:aws:secretsmanager:eu-central-1:149536482038:secret:lamp-db-credentials-endpoint-pcBaRR",
          "arn:aws:secretsmanager:eu-central-1:149536482038:secret:lamp-db-credentials-username-BIeGTd",
          "arn:aws:secretsmanager:eu-central-1:149536482038:secret:lamp-db-credentials-password-yO18l1",
          "arn:aws:secretsmanager:eu-central-1:149536482038:secret:lamp-db-credentials-dbname-miKMTX"
          
        ]
      }
    ]
  })
}

# Attach ecs_secrets_access Policy
resource "aws_iam_role_policy_attachment" "ecs_secrets_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = aws_iam_policy.ecs_secrets_access.arn
}

# Create Log Group via Terraform
resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/${var.cluster_name}"
  retention_in_days = 7
  region            = var.region
}


# ECS Task Definition using Secrets Manager
resource "aws_ecs_task_definition" "this" {
  family                   = var.task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = var.container_name
      image     = var.container_image
      portMappings = [{
        containerPort = 80,
        hostPort      = 80
      }],
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = "/ecs/${var.cluster_name}",
          awslogs-region        = var.region,
          awslogs-stream-prefix = "lamp"
        }
      },
      secrets = [
        {
          name      = "DB_ENDPOINT"
          valueFrom = "arn:aws:secretsmanager:eu-central-1:149536482038:secret:lamp-db-credentials-endpoint-pcBaRR"
        },
        {
          name      = "DB_USERNAME"
          valueFrom = "arn:aws:secretsmanager:eu-central-1:149536482038:secret:lamp-db-credentials-username-BIeGTd"
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = "arn:aws:secretsmanager:eu-central-1:149536482038:secret:lamp-db-credentials-password-yO18l1"
        },
        {
          name      = "DB_NAME"
          valueFrom = "arn:aws:secretsmanager:eu-central-1:149536482038:secret:lamp-db-credentials-dbname-miKMTX"
        }
      ]
    }
  ])
}

# ECS Fargate Service in DR region (Pilot Light: desired_count = 0)
resource "aws_ecs_service" "this" {
  name            = var.service_name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  launch_type     = "FARGATE"
  # Pilot light: No running tasks until DR activated
  desired_count   = 0
  

  # Associate service with ALB
  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.container_name       
    container_port   = 80                       
  }

  network_configuration {
    subnets         = var.private_subnets
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  deployment_controller {
    type = "ECS"
  }

  depends_on = [
    aws_ecs_task_definition.this,
  ]
}




