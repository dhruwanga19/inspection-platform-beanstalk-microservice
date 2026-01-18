# terraform/rds.tf
# RDS MySQL with Multi-AZ and Read Replica

# Parameter Group for MySQL 8.0
resource "aws_db_parameter_group" "mysql" {
  family = "mysql8.0"
  name   = "inspection-${var.environment}-mysql-params"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  parameter {
    name  = "max_connections"
    value = "100"
  }

  tags = {
    Name = "inspection-${var.environment}-mysql-params"
  }
}

# Primary RDS Instance (Multi-AZ)
resource "aws_db_instance" "primary" {
  identifier = "inspection-${var.environment}-mysql-primary"

  # Engine
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro" # Free tier eligible
  parameter_group_name = aws_db_parameter_group.mysql.name

  # Storage
  allocated_storage     = 20
  max_allocated_storage = 100 # Enable autoscaling up to 100GB
  storage_type          = "gp2"
  storage_encrypted     = false # Free tier: encryption adds cost

  # Database
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 3306

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # High Availability - FREE TIER COMPATIBLE
  # Note: Multi-AZ is NOT free tier eligible, but keeping for HA requirement
  # Set to false if you want to stay within free tier
  multi_az = var.enable_multi_az

  # Backup & Maintenance - FREE TIER COMPATIBLE
  backup_retention_period    = var.enable_multi_az ? 7 : 1 # Free tier: max 1 day
  backup_window              = "03:00-04:00"
  maintenance_window         = "Mon:04:00-Mon:05:00"
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true
  deletion_protection        = false

  # Performance Insights - DISABLED for free tier
  performance_insights_enabled = false

  # Enhanced Monitoring - DISABLED for free tier
  monitoring_interval = 0

  # Final snapshot
  skip_final_snapshot       = true
  final_snapshot_identifier = "inspection-${var.environment}-final-snapshot"

  tags = {
    Name = "inspection-${var.environment}-mysql-primary"
    Role = "primary"
  }
}

# Read Replica
resource "aws_db_instance" "read_replica" {
  identifier = "inspection-${var.environment}-mysql-replica"

  # Replica configuration
  replicate_source_db = aws_db_instance.primary.identifier
  instance_class      = "db.t3.micro"

  # Storage (inherited from primary)
  storage_encrypted = false

  # Network
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Replica doesn't need Multi-AZ
  multi_az = false

  # Backup (disable on replica)
  backup_retention_period = 0

  # Maintenance
  auto_minor_version_upgrade = true

  # Performance Insights - DISABLED for free tier
  performance_insights_enabled = false

  # Enhanced Monitoring - DISABLED for free tier
  monitoring_interval = 0

  # Final snapshot
  skip_final_snapshot = true

  tags = {
    Name = "inspection-${var.environment}-mysql-replica"
    Role = "read-replica"
  }

  depends_on = [aws_db_instance.primary]
}

# CloudWatch Alarms for RDS
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "inspection-${var.environment}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU utilization is high"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.primary.identifier
  }

  tags = {
    Name = "inspection-${var.environment}-rds-cpu-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "inspection-${var.environment}-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS connection count is high"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.primary.identifier
  }

  tags = {
    Name = "inspection-${var.environment}-rds-connections-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "inspection-${var.environment}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5368709120 # 5GB in bytes
  alarm_description   = "RDS free storage is low"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.primary.identifier
  }

  tags = {
    Name = "inspection-${var.environment}-rds-storage-alarm"
  }
}

# Outputs
output "rds_primary_endpoint" {
  description = "RDS primary endpoint"
  value       = aws_db_instance.primary.endpoint
}

output "rds_primary_address" {
  description = "RDS primary address (hostname only)"
  value       = aws_db_instance.primary.address
}

output "rds_replica_endpoint" {
  description = "RDS read replica endpoint"
  value       = aws_db_instance.read_replica.endpoint
}

output "rds_replica_address" {
  description = "RDS read replica address (hostname only)"
  value       = aws_db_instance.read_replica.address
}
