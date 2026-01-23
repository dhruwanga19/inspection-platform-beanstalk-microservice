# terraform/elasticbeanstalk.tf
# Elastic Beanstalk Application and Environments

# Elastic Beanstalk Application
resource "aws_elastic_beanstalk_application" "main" {
  name        = "inspection-platform"
  description = "Inspection Platform Application"

  appversion_lifecycle {
    service_role          = aws_iam_role.beanstalk_service.arn
    max_count             = 10
    delete_source_from_s3 = true
  }

  tags = {
    Name = "inspection-platform"
  }
}

# ==================== FRONTEND ENVIRONMENT ====================
resource "aws_elastic_beanstalk_environment" "frontend" {
  name                = "inspection-frontend-${var.environment}"
  application         = aws_elastic_beanstalk_application.main.name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.nodejs.name
  tier                = "WebServer"

  # VPC Configuration
  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = aws_vpc.main.id
  }
  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = join(",", aws_subnet.private[*].id)
  }
  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBSubnets"
    value     = join(",", aws_subnet.public[*].id)
  }
  setting {
    namespace = "aws:ec2:vpc"
    name      = "AssociatePublicIpAddress"
    value     = "false"
  }

  # Instance Configuration
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = "t3.micro"
  }
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.beanstalk_ec2.name
  }
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "SecurityGroups"
    value     = aws_security_group.frontend.id
  }

  # Auto Scaling
  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MinSize"
    value     = "1"
  }
  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MaxSize"
    value     = "4"
  }

  # ==================== SHARED LOAD BALANCER CONFIGURATION ====================
  # Use shared ALB instead of creating a dedicated one
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "LoadBalanced"
  }
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerType"
    value     = "application"
  }
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerIsShared"
    value     = "true"
  }
  setting {
    namespace = "aws:elbv2:loadbalancer"
    name      = "SharedLoadBalancer"
    value     = aws_lb.main.arn
  }
  setting {
    namespace = "aws:elbv2:loadbalancer"
    name      = "SecurityGroups"
    value     = aws_security_group.alb.id
  }

  # Listener rule configuration for path-based routing (catch-all for frontend)
  setting {
    namespace = "aws:elbv2:listenerrule:frontendrule"
    name      = "PathPatterns"
    value     = "/*"
  }
  setting {
    namespace = "aws:elbv2:listenerrule:frontendrule"
    name      = "Priority"
    value     = "999"
  }

  # Deployment Policy (Blue/Green via Immutable)
  setting {
    namespace = "aws:elasticbeanstalk:command"
    name      = "DeploymentPolicy"
    value     = "Immutable"
  }
  setting {
    namespace = "aws:elasticbeanstalk:command"
    name      = "Timeout"
    value     = "600"
  }

  # Health Reporting
  setting {
    namespace = "aws:elasticbeanstalk:healthreporting:system"
    name      = "SystemType"
    value     = "enhanced"
  }

  # Health Check for Frontend
  setting {
    namespace = "aws:elasticbeanstalk:environment:process:default"
    name      = "HealthCheckPath"
    value     = "/health"
  }
  setting {
    namespace = "aws:elasticbeanstalk:environment:process:default"
    name      = "Port"
    value     = "8080"
  }

  # Environment Variables
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "PORT"
    value     = "8080"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "NODE_ENV"
    value     = "production"
  }

  tags = {
    Name        = "inspection-frontend-${var.environment}"
    Environment = var.environment
    Service     = "frontend"
  }

  depends_on = [aws_nat_gateway.main, aws_lb.main, aws_lb_listener.http]
}

# ==================== INSPECTION API ENVIRONMENT ====================
resource "aws_elastic_beanstalk_environment" "inspection_api" {
  name                = "inspection-api-${var.environment}"
  application         = aws_elastic_beanstalk_application.main.name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.nodejs.name
  tier                = "WebServer"

  # VPC Configuration
  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = aws_vpc.main.id
  }
  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = join(",", aws_subnet.private[*].id)
  }
  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBSubnets"
    value     = join(",", aws_subnet.public[*].id)
  }
  setting {
    namespace = "aws:ec2:vpc"
    name      = "AssociatePublicIpAddress"
    value     = "false"
  }

  # Instance Configuration
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = "t3.micro"
  }
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.beanstalk_ec2.name
  }
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "SecurityGroups"
    value     = aws_security_group.inspection_api.id
  }

  # Auto Scaling
  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MinSize"
    value     = "1"
  }
  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MaxSize"
    value     = "4"
  }

  # Auto Scaling Triggers
  setting {
    namespace = "aws:autoscaling:trigger"
    name      = "MeasureName"
    value     = "CPUUtilization"
  }
  setting {
    namespace = "aws:autoscaling:trigger"
    name      = "Statistic"
    value     = "Average"
  }
  setting {
    namespace = "aws:autoscaling:trigger"
    name      = "Unit"
    value     = "Percent"
  }
  setting {
    namespace = "aws:autoscaling:trigger"
    name      = "UpperThreshold"
    value     = "70"
  }
  setting {
    namespace = "aws:autoscaling:trigger"
    name      = "LowerThreshold"
    value     = "30"
  }

  # ==================== SHARED LOAD BALANCER CONFIGURATION ====================
  # Use shared ALB instead of creating a dedicated one
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "LoadBalanced"
  }
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerType"
    value     = "application"
  }
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerIsShared"
    value     = "true"
  }
  setting {
    namespace = "aws:elbv2:loadbalancer"
    name      = "SharedLoadBalancer"
    value     = aws_lb.main.arn
  }
  setting {
    namespace = "aws:elbv2:loadbalancer"
    name      = "SecurityGroups"
    value     = aws_security_group.alb.id
  }

  # Listener rule configuration for path-based routing
  setting {
    namespace = "aws:elbv2:listenerrule:inspectionapirule"
    name      = "PathPatterns"
    value     = "/api/inspections,/api/inspections/*,/api/presigned-url"
  }
  setting {
    namespace = "aws:elbv2:listenerrule:inspectionapirule"
    name      = "Priority"
    value     = "100"
  }

  # Health Check
  setting {
    namespace = "aws:elasticbeanstalk:environment:process:default"
    name      = "HealthCheckPath"
    value     = "/health"
  }
  setting {
    namespace = "aws:elasticbeanstalk:environment:process:default"
    name      = "Port"
    value     = "3001"
  }

  # Deployment Policy (Blue/Green via Immutable)
  setting {
    namespace = "aws:elasticbeanstalk:command"
    name      = "DeploymentPolicy"
    value     = "Immutable"
  }

  # Health Reporting
  setting {
    namespace = "aws:elasticbeanstalk:healthreporting:system"
    name      = "SystemType"
    value     = "enhanced"
  }

  # Environment Variables
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "NODE_ENV"
    value     = "production"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "PORT"
    value     = "3001"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_HOST"
    value     = aws_db_instance.primary.address
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_PORT"
    value     = "3306"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_NAME"
    value     = var.db_name
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_USER"
    value     = var.db_username
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_PASSWORD"
    value     = var.db_password
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "IMAGE_BUCKET_NAME"
    value     = aws_s3_bucket.images.id
  }

  tags = {
    Name        = "inspection-api-${var.environment}"
    Environment = var.environment
    Service     = "inspection-api"
  }

  depends_on = [aws_db_instance.primary, aws_nat_gateway.main, aws_lb.main, aws_lb_listener.http]
}

# ==================== REPORT SERVICE ENVIRONMENT ====================
resource "aws_elastic_beanstalk_environment" "report_service" {
  name                = "report-service-${var.environment}"
  application         = aws_elastic_beanstalk_application.main.name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.nodejs.name
  tier                = "WebServer"

  # VPC Configuration
  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = aws_vpc.main.id
  }
  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = join(",", aws_subnet.private[*].id)
  }
  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBSubnets"
    value     = join(",", aws_subnet.public[*].id)
  }
  setting {
    namespace = "aws:ec2:vpc"
    name      = "AssociatePublicIpAddress"
    value     = "false"
  }

  # Instance Configuration
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = "t3.micro"
  }
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.beanstalk_ec2.name
  }
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "SecurityGroups"
    value     = aws_security_group.report_service.id
  }

  # Auto Scaling
  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MinSize"
    value     = "1"
  }
  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MaxSize"
    value     = "4"
  }

  # ==================== SHARED LOAD BALANCER CONFIGURATION ====================
  # Use shared ALB instead of creating a dedicated one
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "LoadBalanced"
  }
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerType"
    value     = "application"
  }
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerIsShared"
    value     = "true"
  }
  setting {
    namespace = "aws:elbv2:loadbalancer"
    name      = "SharedLoadBalancer"
    value     = aws_lb.main.arn
  }
  setting {
    namespace = "aws:elbv2:loadbalancer"
    name      = "SecurityGroups"
    value     = aws_security_group.alb.id
  }

  # Listener rule configuration for path-based routing
  setting {
    namespace = "aws:elbv2:listenerrule:reportservicerule"
    name      = "PathPatterns"
    value     = "/api/reports,/api/reports/*"
  }
  setting {
    namespace = "aws:elbv2:listenerrule:reportservicerule"
    name      = "Priority"
    value     = "110"
  }

  # Health Check
  setting {
    namespace = "aws:elasticbeanstalk:environment:process:default"
    name      = "HealthCheckPath"
    value     = "/health"
  }
  setting {
    namespace = "aws:elasticbeanstalk:environment:process:default"
    name      = "Port"
    value     = "3002"
  }

  # Deployment Policy (Blue/Green via Immutable)
  setting {
    namespace = "aws:elasticbeanstalk:command"
    name      = "DeploymentPolicy"
    value     = "Immutable"
  }

  # Health Reporting
  setting {
    namespace = "aws:elasticbeanstalk:healthreporting:system"
    name      = "SystemType"
    value     = "enhanced"
  }

  # Environment Variables
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "NODE_ENV"
    value     = "production"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "PORT"
    value     = "3002"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_HOST"
    value     = aws_db_instance.primary.address
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_READ_HOST"
    value     = aws_db_instance.read_replica.address
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_PORT"
    value     = "3306"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_NAME"
    value     = var.db_name
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_USER"
    value     = var.db_username
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_PASSWORD"
    value     = var.db_password
  }

  tags = {
    Name        = "report-service-${var.environment}"
    Environment = var.environment
    Service     = "report-service"
  }

  depends_on = [aws_db_instance.primary, aws_db_instance.read_replica, aws_nat_gateway.main, aws_lb.main, aws_lb_listener.http]
}
