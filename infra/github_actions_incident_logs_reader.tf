# Read-only role for GitHub Actions: incident log reports (FilterLogEvents only).
# Requires an existing OIDC provider for token.actions.githubusercontent.com (same as deploy role).

locals {
  incident_logs_reader_count = (
    var.enable_ecs && var.enable_github_incident_logs_reader_role ? 1 : 0
  )
}

data "aws_iam_openid_connect_provider" "github" {
  count = local.incident_logs_reader_count
  url   = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_incident_logs_reader" {
  count = local.incident_logs_reader_count

  name = "${local.name_prefix}-github-incident-logs-reader"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github[0].arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" : "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" : "repo:${var.github_actions_oidc_repository}:*"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-github-incident-logs-reader"
  })
}

resource "aws_iam_role_policy" "github_incident_logs_reader" {
  count = local.incident_logs_reader_count

  name = "${local.name_prefix}-cloudwatch-filter-ecs-logs"
  role = aws_iam_role.github_incident_logs_reader[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "FilterLogEventsOnEcsServiceGroup"
        Effect = "Allow"
        Action = [
          "logs:FilterLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.ecs[0].arn}:*"
      }
    ]
  })
}
