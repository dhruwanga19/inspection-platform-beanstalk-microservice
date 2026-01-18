# terraform/outputs.tf
# Consolidated outputs for the infrastructure

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "database_subnet_ids" {
  description = "Database subnet IDs"
  value       = aws_subnet.database[*].id
}

# Elastic Beanstalk Outputs
output "eb_application_name" {
  description = "Elastic Beanstalk application name"
  value       = aws_elastic_beanstalk_application.main.name
}

output "eb_frontend_environment" {
  description = "Frontend Elastic Beanstalk environment name"
  value       = aws_elastic_beanstalk_environment.frontend.name
}

output "eb_frontend_endpoint" {
  description = "Frontend Elastic Beanstalk endpoint URL"
  value       = aws_elastic_beanstalk_environment.frontend.endpoint_url
}

output "eb_inspection_api_environment" {
  description = "Inspection API Elastic Beanstalk environment name"
  value       = aws_elastic_beanstalk_environment.inspection_api.name
}

output "eb_inspection_api_endpoint" {
  description = "Inspection API Elastic Beanstalk endpoint URL"
  value       = aws_elastic_beanstalk_environment.inspection_api.endpoint_url
}

output "eb_report_service_environment" {
  description = "Report Service Elastic Beanstalk environment name"
  value       = aws_elastic_beanstalk_environment.report_service.name
}

output "eb_report_service_endpoint" {
  description = "Report Service Elastic Beanstalk endpoint URL"
  value       = aws_elastic_beanstalk_environment.report_service.endpoint_url
}

# Application URL
output "application_url" {
  description = "Main application URL (ALB)"
  value       = "http://${aws_lb.main.dns_name}"
}

# Database connection info (sensitive)
output "database_connection_info" {
  description = "Database connection information"
  value = {
    primary_host  = aws_db_instance.primary.address
    replica_host  = aws_db_instance.read_replica.address
    port          = 3306
    database_name = var.db_name
  }
  sensitive = true
}

# Summary output for quick reference
output "deployment_summary" {
  description = "Summary of deployed resources"
  value       = <<-EOT
    
    ============================================
    INSPECTION PLATFORM - DEPLOYMENT SUMMARY
    ============================================
    
    APPLICATION URL: http://${aws_lb.main.dns_name}
    
    ROUTING:
      /                     -> Frontend (React SPA)
      /api/inspections/*    -> Inspection API
      /api/presigned-url    -> Inspection API  
      /api/reports/*        -> Report Service
    
    ELASTIC BEANSTALK ENVIRONMENTS:
      Frontend:       ${aws_elastic_beanstalk_environment.frontend.name}
      Inspection API: ${aws_elastic_beanstalk_environment.inspection_api.name}
      Report Service: ${aws_elastic_beanstalk_environment.report_service.name}
    
    DATABASE:
      Primary:  ${aws_db_instance.primary.address}:3306
      Replica:  ${aws_db_instance.read_replica.address}:3306
      Database: ${var.db_name}
    
    S3 BUCKETS:
      Images:      ${aws_s3_bucket.images.id}
      Deployments: ${aws_s3_bucket.deployments.id}
    
    ============================================
  EOT
}
