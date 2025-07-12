
# Security Group for RDS read replica
resource "aws_security_group" "rds_sg" {
  name        = "rds-replica-sg"
  vpc_id      = var.vpc_id
  description = "Allow MySQL from ECS"

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.ecs_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "dr" {
  name       = "lamp-dr-db-subnet-group"
  subnet_ids = var.private_subnets  # or private_subnet_ids
  tags = {
    Name = "DR Subnet Group"
  }
}

# Create a KMS replica key in the DR region (eu-central-1)
resource "aws_kms_replica_key" "replica" {
  description          = "Replica KMS key for cross-region RDS read replica"
  primary_key_arn      = var.primary_kms_key_arn
  deletion_window_in_days = 7
  enabled              = true
}

# RDS Cross-Region Read Replica
resource "aws_db_instance" "replica" {
  identifier              = var.replica_identifier
  replicate_source_db     = var.source_db_arn
  instance_class          = var.instance_class
  db_subnet_group_name    = aws_db_subnet_group.dr.name
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  multi_az                = false
  publicly_accessible     = false
  storage_encrypted       = true
  skip_final_snapshot     = true

  # Encryption settings for cross-region replica
  kms_key_id              = aws_kms_replica_key.replica.arn

  # Tags
  tags = {
    Name = "lamp-db-dr-replica"
  }
}

# CloudWatch Alarm for Replication Lag
resource "aws_cloudwatch_metric_alarm" "replica_lag_alarm" {
  alarm_name          = "rds-replica-lag-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ReplicaLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 30

  dimensions = {
    DBInstanceIdentifier = var.replica_identifier
  }

  alarm_description = "Triggers if RDS read replica lag exceeds 30 seconds"
  treat_missing_data = "notBreaching"

  alarm_actions = [] # Add SNS topic ARN if you want email/SMS
}
