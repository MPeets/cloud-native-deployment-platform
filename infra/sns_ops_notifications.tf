# SNS topic for CloudWatch alarm actions (subscriptions and alarms added in follow-up commits).
resource "aws_sns_topic" "ops_alerts" {
  count = local.ops_notifications_enabled ? 1 : 0

  name = "${local.name_prefix}-ops-alerts"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ops-alerts"
  })
}
