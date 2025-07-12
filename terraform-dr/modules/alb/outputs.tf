# ALB DNS name 
output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

# Full ARN of the ALB (useful for logging, monitoring, etc.)
output "alb_arn" {
  value = aws_lb.this.arn
}

# ARN of the ALB target group (required by ECS service)
output "target_group_arn" {
  value = aws_lb_target_group.this.arn
}

output "alb_sg_id" {
  value = aws_security_group.alb_sg.id
}
