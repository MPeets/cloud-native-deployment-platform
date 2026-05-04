resource "aws_cloudwatch_metric_alarm" "rds_free_storage_low" {
  count = var.enable_rds && local.ops_notifications_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-rds-free-storage-low"
  alarm_description   = "Free storage on the PostgreSQL instance has fallen below a safety buffer (expand storage or clean up data)."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 2 * 1024 * 1024 * 1024
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = module.rds[0].db_instance_identifier
  }

  alarm_actions = [aws_sns_topic.ops_alerts[0].arn]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-free-storage-low"
  })
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  count = var.enable_rds && local.ops_notifications_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-rds-cpu-high"
  alarm_description   = "Sustained high CPU on the PostgreSQL instance (consider rightsizing, query tuning, or load investigation)."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = module.rds[0].db_instance_identifier
  }

  alarm_actions = [aws_sns_topic.ops_alerts[0].arn]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-cpu-high"
  })
}
