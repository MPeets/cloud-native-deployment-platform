provider "aws" {
  region = var.aws_region
}

resource "aws_security_group" "allow_http" {
  count = var.enable_ec2 ? 1 : 0

  name   = "allow_http"
  vpc_id = aws_vpc.app.id

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "app" {
  count = var.enable_ec2 ? 1 : 0

  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  subnet_id                   = aws_subnet.public[local.nat_public_subnet_key].id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.allow_http[0].id]

  user_data = <<-USERDATA
    #!/bin/bash
    set -e

    apt-get update -y
    apt-get install -y docker.io

    systemctl enable docker
    systemctl start docker

    usermod -aG docker ubuntu || true

    IMAGE="${var.docker_image}"

    cat > /etc/systemd/system/devops-api.service <<UNIT
    [Unit]
    Description=DevOps API Container
    Requires=docker.service
    After=docker.service

    [Service]
    Restart=always
    ExecStart=/usr/bin/docker run --rm --name devops-api -p 3000:3000 $IMAGE
    ExecStop=/usr/bin/docker stop devops-api

    [Install]
    WantedBy=multi-user.target
    UNIT

    systemctl daemon-reload
    systemctl enable devops-api
    systemctl start devops-api
  USERDATA

  tags = {
    Name = "devops-api-instance"
  }
}