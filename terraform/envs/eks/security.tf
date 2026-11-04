# Firewall rules (security groups).
#
#   your home IP --443--> EKS API (public_access_cidrs in eks.tf)
#   your home IP --80--> load balancer --> nodes (rules added by Kubernetes itself, see k8s/05-aws-generated.yaml)
#   nodes (cluster security group) --3306--> RDS
#
# EKS makes one "cluster security group" for the control plane and all managed nodes:
# inside it everything may talk to everything, from outside nothing comes in.

data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  my_ip_cidr = "${trimspace(data.http.my_ip.response_body)}/32" # /32 = exactly one address
  site_cidrs = var.site_open_to_world ? ["0.0.0.0/0"] : [local.my_ip_cidr]
}

resource "aws_security_group" "db" {
  name        = "travelagency-eks-db"
  description = "RDS MySQL: port 3306 only from the EKS nodes"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "MySQL, only from the EKS cluster (nodes and pods)"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.this.vpc_config[0].cluster_security_group_id]
  }

  # No egress block: the database never starts a connection itself.

  tags = { Name = "travelagency-eks-db" }
}