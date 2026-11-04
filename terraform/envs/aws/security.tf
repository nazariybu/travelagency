# Security groups = a firewall in front of every server, the load balancer and RDS.
# Everything that is not allowed here is blocked.
#
#   internet (or only you) --80--> [alb] --8080--> [app] --3306--> [db]
#                                                    \---6379--> [redis]
#   your home IP --22 (SSH: Ansible)--> [app], [redis]

# Your home public IP, asked at every plan. If your provider changes it, the next apply updates the rules.
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  my_ip_cidr = "${trimspace(data.http.my_ip.response_body)}/32" # /32 = exactly one address
  site_cidrs = var.site_open_to_world ? ["0.0.0.0/0"] : [local.my_ip_cidr]
}

resource "aws_security_group" "alb" {
  name        = "travelagency-alb"
  description = "Load balancer: HTTP from the internet or only from home"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = local.site_cidrs
  }

  egress {
    description = "To the app nodes inside the VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # all protocols
    cidr_blocks = [var.network.vpc_cidr]
  }

  tags = { Name = "travelagency-alb" }
}

resource "aws_security_group" "app" {
  name        = "travelagency-app"
  description = "App nodes: Tomcat from the load balancer, SSH from home"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Tomcat, only from the load balancer"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "SSH from home (Ansible)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.my_ip_cidr]
  }

  egress {
    description = "Internet: apt, git clone, Maven; and Redis, RDS inside the VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "travelagency-app" }
}

resource "aws_security_group" "redis" {
  name        = "travelagency-redis"
  description = "Redis: port 6379 only from the app nodes, SSH from home"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Redis, only from the app nodes"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description = "SSH from home (Ansible)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.my_ip_cidr]
  }

  egress {
    description = "Internet: apt"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "travelagency-redis" }
}

resource "aws_security_group" "db" {
  name        = "travelagency-db"
  description = "RDS MySQL: port 3306 only from the app nodes"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "MySQL, only from the app nodes"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  # No egress block: the database never starts a connection itself.

  tags = { Name = "travelagency-db" }
}