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

# NOTE: Target groups are created by Elastic Beanstalk environments.
# However, EB creates listener rules with host-header conditions that only work
# when accessing via the EB environment URL, not the ALB DNS directly.
#
# The rules below create path-only listener rules that work with the ALB DNS.
# They reference the target groups created by EB environments.

# ==================== PATH-ONLY LISTENER RULES ====================
# These rules enable path-based routing via the ALB DNS (without host-header conditions)

# Data sources to get EB-created target groups
data "aws_lb_target_group" "frontend" {
  tags = {
    "elasticbeanstalk:environment-name" = aws_elastic_beanstalk_environment.frontend.name
  }
  depends_on = [aws_elastic_beanstalk_environment.frontend]
}

data "aws_lb_target_group" "inspection_api" {
  tags = {
    "elasticbeanstalk:environment-name" = aws_elastic_beanstalk_environment.inspection_api.name
  }
  depends_on = [aws_elastic_beanstalk_environment.inspection_api]
}

data "aws_lb_target_group" "report_service" {
  tags = {
    "elasticbeanstalk:environment-name" = aws_elastic_beanstalk_environment.report_service.name
  }
  depends_on = [aws_elastic_beanstalk_environment.report_service]
}

# Listener rule for Inspection API (path-only, no host-header)
resource "aws_lb_listener_rule" "inspection_api_path" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = data.aws_lb_target_group.inspection_api.arn
  }

  condition {
    path_pattern {
      values = ["/api/inspections", "/api/inspections/*", "/api/presigned-url"]
    }
  }

  tags = {
    Name = "inspection-api-path-rule"
  }

  depends_on = [aws_elastic_beanstalk_environment.inspection_api]
}

# Listener rule for Report Service (path-only, no host-header)
resource "aws_lb_listener_rule" "report_service_path" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 110

  action {
    type             = "forward"
    target_group_arn = data.aws_lb_target_group.report_service.arn
  }

  condition {
    path_pattern {
      values = ["/api/reports", "/api/reports/*"]
    }
  }

  tags = {
    Name = "report-service-path-rule"
  }

  depends_on = [aws_elastic_beanstalk_environment.report_service]
}

# Listener rule for Frontend catch-all (path-only, no host-header)
resource "aws_lb_listener_rule" "frontend_path" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 999

  action {
    type             = "forward"
    target_group_arn = data.aws_lb_target_group.frontend.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  tags = {
    Name = "frontend-path-rule"
  }

  depends_on = [aws_elastic_beanstalk_environment.frontend]
}

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
