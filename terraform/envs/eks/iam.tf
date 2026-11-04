# IAM roles = "badges" with rights that AWS services wear.
# EKS itself and every node (EC2) act in your account, so each needs its own role.
# Names start with "travelagency-": the policy of your Terraform user allows only such roles (step 3).

# --- 1. Role of the EKS control plane ---
# EKS uses it to manage network cards in our subnets and to create load balancers for Services.

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"] # only the EKS service may wear this badge
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "travelagency-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy" # ready policy made by AWS
}

# --- 2. Role of the worker nodes ---
# Every node (EC2) wears it: join the cluster, give pods IP addresses, download EKS system images.

data "aws_iam_policy_document" "nodes_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "nodes" {
  name               = "travelagency-eks-nodes"
  assume_role_policy = data.aws_iam_policy_document.nodes_assume.json
}

resource "aws_iam_role_policy_attachment" "nodes" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",          # join the cluster
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",               # VPC CNI: every pod gets an IP from the VPC
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly", # pull EKS system images (kube-proxy, CoreDNS ...)
  ])

  role       = aws_iam_role.nodes.name
  policy_arn = each.value
}