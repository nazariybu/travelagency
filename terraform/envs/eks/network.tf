# Our own private network in AWS (VPC), the same idea as envs/aws.
#
#   VPC 10.30.0.0/16 "travelagency-eks"
#   ├── public a  10.30.1.0/24   EKS nodes, load balancer, EKS control plane network cards
#   ├── public b  10.30.2.0/24   the same (EKS wants at least 2 zones)
#   ├── db a      10.30.11.0/24  RDS, NO route to the internet
#   └── db b      10.30.12.0/24  RDS
#
# No NAT gateway (~35 $/month): the nodes are in public subnets with a public IP,
# they need the internet to download images (Docker Hub). Nothing can connect TO them from the internet:
# the security group of the cluster blocks it (security.tf).

resource "aws_vpc" "this" {
  cidr_block           = var.network.vpc_cidr
  enable_dns_support   = true # DNS inside the VPC: the RDS address and the private EKS API are names
  enable_dns_hostnames = true

  tags = { Name = "travelagency-eks" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "travelagency-eks" }
}

resource "aws_subnet" "public" {
  for_each = var.network.public_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = "${var.aws_region}${each.key}" # eu-central-1a, eu-central-1b
  map_public_ip_on_launch = true                           # every node gets a public IP (no NAT)

  tags = {
    Name = "travelagency-eks-public-${each.key}"
    # Kubernetes looks for this tag when it creates a public load balancer (Service type LoadBalancer)
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "db" {
  for_each = var.network.db_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = "${var.aws_region}${each.key}"

  tags = { Name = "travelagency-eks-db-${each.key}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "travelagency-eks-public" }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# DB subnets have no association: the main route table knows only "local" (10.30.0.0/16).