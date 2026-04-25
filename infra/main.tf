provider "aws" {
  region = var.aws_region
}

resource "aws_security_group" "allow_http" {
  name = "allow_http"

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
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "app" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.allow_http.id]

    user_data = <<-EOF
                 #!/bin/bash
                 set -e

                 apt update -y
                 apt install -y docker.io

                 systemctl enable docker
                 systemctl start docker

                 usermod -aG docker ubuntu || true
                 
                 cat <<EOF > /etc/systemd/system/devops-api.service
                 [Unit]
                 Description=DevOps API Container
                 After=docker.service
                 Requires=docker.service

                 [Service]
                 Restart=always
                 ExecStart=/usr/bin/docker run --name devops-api -p 3000:3000 mpeets/devops-api:latest
                 ExecStop=/usr/bin/docker stop devops-api
                 ExecStopPost=/usr/bin/docker rm -f devops-api

                 [Install]
                 WantedBy=multi-user.target

                 systemctl daemon-reload
                 systemctl enable devops-api
                 systemctl start devops-api
                 EOF

  tags = {
    Name = "devops-api-instance"
  }
}