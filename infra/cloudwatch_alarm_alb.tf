resource "aws_cloudwatch_metric_alarm" "alb_target_5xx" {
  count = var.enable_ecs && local.ops_notifications_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-alb-target-5xx"
  alarm_description   = "Fires when targets return several HTTP 5xx responses in one interval (possible app or health issues)."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = module.alb[0].load_balancer_arn_suffix
    TargetGroup  = module.alb[0].target_group_arn_suffix
  }

  alarm_actions = [aws_sns_topic.ops_alerts[0].arn]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-target-5xx"
  })
}
