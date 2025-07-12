# Security Group for ALB to allow inbound HTTP traffic and outbound responses
resource "aws_security_group" "alb_sg" {
  name        = "${var.name}-alb-sg"
  description = "Allow HTTP/HTTPS traffic to ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Open to the internet (can be restricted)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]  # Allow all outbound traffic
  }

  tags = var.tags
}

# Application Load Balancer (ALB)
resource "aws_lb" "this" {
  name               = var.name
  internal           = false                       # Public-facing
  load_balancer_type = "application"               # ALB type
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.public_subnets          # Attach to public subnets
  enable_deletion_protection = false               # Can delete in DR if needed

  tags = var.tags
}

# Target group for routing traffic to ECS tasks (IP mode)
resource "aws_lb_target_group" "this" {
  name        = "${var.name}-tg"
  port        = 80                                 # ECS container port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"                               # Required for Fargate

  health_check {
    path                = "/"                      # Health check path
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = var.tags
}

# HTTP Listener for port 80 to forward requests to the target group
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
