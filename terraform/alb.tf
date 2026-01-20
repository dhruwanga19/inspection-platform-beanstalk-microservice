# Shared ALB for all Elastic Beanstalk environments
# Path-based routing is managed by EB environments using this shared ALB
resource "aws_lb" "main" {
  name               = "inspection-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false # Set to true for production

  tags = {
    Name = "inspection-${var.environment}-alb"
  }
}

# ALB Listener (HTTP - use HTTPS in production with ACM certificate)
# Default action returns 404 - actual routing is handled by EB-managed listener rules
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "No matching route found"
      status_code  = "404"
    }
  }

  tags = {
    Name = "inspection-${var.environment}-http-listener"
  }
}

# NOTE: Target groups and listener rules are now managed by Elastic Beanstalk
# Each EB environment creates its own target group and listener rule
# with path-based routing configured in elasticbeanstalk.tf
#
# Routing Configuration:
# - /api/inspections/*, /api/presigned-url -> Inspection API (Priority 100)
# - /api/reports/*                         -> Report Service (Priority 110)
# - /* (catch-all)                         -> Frontend (Priority 999)

# ==================== OUTPUTS ====================
output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "ALB Zone ID for Route 53"
  value       = aws_lb.main.zone_id
}

output "alb_arn" {
  description = "ALB ARN for shared load balancer configuration"
  value       = aws_lb.main.arn
}

output "alb_listener_arn" {
  description = "ALB HTTP Listener ARN"
  value       = aws_lb_listener.http.arn
}
