# terraform/main.tf
# Main Terraform configuration for 3-Tier HA Architecture

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "inspection-platform"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# ==================== VARIABLES ====================
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "inspection_platform"
}

variable "enable_multi_az" {
  description = "Enable Multi-AZ for RDS (not free tier eligible)"
  type        = bool
  default     = true # Set to false to stay within free tier
}

variable "rds_publicly_accessible" {
  description = "Make RDS publicly accessible (for development only!)"
  type        = bool
  default     = false
}

variable "my_ip_cidr" {
  description = "Your IP address in CIDR notation for RDS access (e.g., 1.2.3.4/32)"
  type        = string
  default     = "" # Leave empty to skip the rule
}

# Data source to get the latest Node.js 20 solution stack
data "aws_elastic_beanstalk_solution_stack" "nodejs" {
  most_recent = true
  name_regex  = "^64bit Amazon Linux 2023 v[0-9.]+ running Node.js 20$"
}

# ==================== VPC ====================
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "inspection-${var.environment}-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "inspection-${var.environment}-igw"
  }
}

# Public Subnets (for ALB and NAT Gateway)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "inspection-${var.environment}-public-${count.index + 1}"
    Type = "public"
  }
}

# Private Subnets (for Elastic Beanstalk EC2 instances)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 11)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "inspection-${var.environment}-private-${count.index + 1}"
    Type = "private"
  }
}

# Database Subnets
resource "aws_subnet" "database" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 21)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "inspection-${var.environment}-database-${count.index + 1}"
    Type = "database"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "inspection-${var.environment}-nat-eip"
  }

  depends_on = [aws_internet_gateway.main]
}

# NAT Gateway
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "inspection-${var.environment}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "inspection-${var.environment}-public-rt"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "inspection-${var.environment}-private-rt"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "database" {
  count          = 2
  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.private.id
}

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "inspection-${var.environment}-db-subnet-group"
  subnet_ids = aws_subnet.database[*].id

  tags = {
    Name = "inspection-${var.environment}-db-subnet-group"
  }
}
