# Main ALB for path-based routing to all services
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
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# Target Group - Frontend
resource "aws_lb_target_group" "frontend" {
  name        = "inspection-${var.environment}-frontend-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "inspection-${var.environment}-frontend-tg"
  }
}

# Target Group - Inspection API
resource "aws_lb_target_group" "inspection_api" {
  name        = "inspection-${var.environment}-api-tg"
  port        = 3001
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "inspection-${var.environment}-api-tg"
  }
}

# Target Group - Report Service
resource "aws_lb_target_group" "report_service" {
  name        = "inspection-${var.environment}-report-tg"
  port        = 3002
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "inspection-${var.environment}-report-tg"
  }
}

# Listener Rule - Inspection API (/api/inspections/*, /api/presigned-url)
resource "aws_lb_listener_rule" "inspection_api" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.inspection_api.arn
  }

  condition {
    path_pattern {
      values = ["/api/inspections", "/api/inspections/*", "/api/presigned-url"]
    }
  }
}

# Listener Rule - Report Service (/api/reports/*)
resource "aws_lb_listener_rule" "report_service" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 110

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.report_service.arn
  }

  condition {
    path_pattern {
      values = ["/api/reports", "/api/reports/*"]
    }
  }
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
