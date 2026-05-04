# Alerts when the API service is not running enough tasks to match desired count
# (failed tasks, steady partial outages, or deploys stuck mid-rollout).
resource "aws_cloudwatch_metric_alarm" "ecs_api_task_shortfall" {
  count = var.enable_ecs && local.ops_notifications_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-ecs-api-task-shortfall"
  alarm_description   = "Running tasks are below desired count for the API ECS service."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 0
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "e1"
    expression  = "m2-m1"
    label       = "Desired minus running"
    return_data = true
  }

  metric_query {
    id = "m1"
    metric {
      metric_name = "RunningTaskCount"
      namespace   = "AWS/ECS"
      period      = 60
      stat        = "Average"
      dimensions = {
        ClusterName = local.name_prefix
        ServiceName = "${local.name_prefix}-api"
      }
    }
  }

  metric_query {
    id = "m2"
    metric {
      metric_name = "DesiredTaskCount"
      namespace   = "AWS/ECS"
      period      = 60
      stat        = "Average"
      dimensions = {
        ClusterName = local.name_prefix
        ServiceName = "${local.name_prefix}-api"
      }
    }
  }

  alarm_actions = [aws_sns_topic.ops_alerts[0].arn]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-api-task-shortfall"
  })
}
