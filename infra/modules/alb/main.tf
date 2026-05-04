locals {
  certificate_arn_trimmed = var.certificate_arn != null ? trimspace(var.certificate_arn) : ""
  use_https               = local.certificate_arn_trimmed != ""
}

resource "aws_security_group" "this" {
  name   = "${var.name_prefix}-alb"
  vpc_id = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-alb-sg"
  })

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = local.use_https ? [443] : []
    content {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "this" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.this.id]
  subnets            = var.public_subnet_ids

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-alb"
  })
}

resource "aws_lb_target_group" "this" {
  name        = "${var.name_prefix}-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-tg"
  })

  health_check {
    path                = var.alb_health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 15
    matcher             = "200-399"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = local.use_https ? "redirect" : "forward"
    target_group_arn = local.use_https ? null : aws_lb_target_group.this.arn

    dynamic "redirect" {
      for_each = local.use_https ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

resource "aws_lb_listener" "https" {
  count = local.use_https ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = local.certificate_arn_trimmed

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
