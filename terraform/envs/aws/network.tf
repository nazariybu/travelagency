# Our own private network in AWS (VPC). Like the home network 192.168.18.0/24 behind the router.
#
#   VPC 10.20.0.0/16 "travelagency"
#   ├── public a  10.20.1.0/24   app1, redis, load balancer   route to the internet
#   ├── public b  10.20.2.0/24   app2, load balancer          route to the internet
#   ├── db a      10.20.11.0/24  RDS                          NO route to the internet
#   └── db b      10.20.12.0/24  RDS (AWS wants 2 zones even for one DB server)
#
# No NAT gateway on purpose: it costs about 35 $ a month. The servers are in public subnets,
# and the security groups (security.tf) decide who may reach them.

resource "aws_vpc" "this" {
  cidr_block           = var.network.vpc_cidr
  enable_dns_support   = true # DNS inside the VPC: the RDS address is a name, not an IP
  enable_dns_hostnames = true

  tags = { Name = "travelagency" }
}

# The "router" to the internet
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "travelagency" }
}

# for_each over { a = "10.20.1.0/24", b = "10.20.2.0/24" }: one subnet per zone
resource "aws_subnet" "public" {
  for_each = var.network.public_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = "${var.aws_region}${each.key}" # eu-central-1a, eu-central-1b
  map_public_ip_on_launch = true

  tags = { Name = "travelagency-public-${each.key}" }
}

resource "aws_subnet" "db" {
  for_each = var.network.db_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = "${var.aws_region}${each.key}"

  tags = { Name = "travelagency-db-${each.key}" }
}

# Public subnets: "everything that is not inside the VPC goes to the internet gateway"
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "travelagency-public" }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# DB subnets have no association: they use the main route table of the VPC,
# which knows only "local" (10.20.0.0/16). RDS cannot reach the internet, the internet cannot reach RDS.