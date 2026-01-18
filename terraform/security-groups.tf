# Security Groups for 3-Tier Architecture

# ALB Security Group
resource "aws_security_group" "alb" {
  name        = "inspection-${var.environment}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "inspection-${var.environment}-alb-sg"
  }
}

# Frontend EC2 Security Group
resource "aws_security_group" "frontend" {
  name        = "inspection-${var.environment}-frontend-sg"
  description = "Security group for Frontend Elastic Beanstalk instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "inspection-${var.environment}-frontend-sg"
  }
}

# Inspection API Security Group
resource "aws_security_group" "inspection_api" {
  name        = "inspection-${var.environment}-inspection-api-sg"
  description = "Security group for Inspection API Elastic Beanstalk instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 3001
    to_port         = 3001
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "inspection-${var.environment}-inspection-api-sg"
  }
}

# Report Service Security Group
resource "aws_security_group" "report_service" {
  name        = "inspection-${var.environment}-report-service-sg"
  description = "Security group for Report Service Elastic Beanstalk instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 3002
    to_port         = 3002
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "inspection-${var.environment}-report-service-sg"
  }
}

# RDS Security Group
resource "aws_security_group" "rds" {
  name        = "inspection-${var.environment}-rds-sg"
  description = "Security group for RDS MySQL"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from Inspection API"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.inspection_api.id]
  }

  ingress {
    description     = "MySQL from Report Service"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.report_service.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "inspection-${var.environment}-rds-sg"
  }
}
