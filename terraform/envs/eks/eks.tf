# The Kubernetes cluster. EKS = AWS runs the control plane (API server, etcd, scheduler) for us,
# in 2+ zones, updates and backs it up. We pay 0.10 $/hour for it and do not see its servers.
# We only add worker nodes (EC2) where our pods run.

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids = [for s in aws_subnet.public : s.id]

    # The API (what kubectl talks to) has two doors:
    endpoint_private_access = true               # inside the VPC: the nodes use this one
    endpoint_public_access  = true               # from the internet: your kubectl at home ...
    public_access_cidrs     = [local.my_ip_cidr] # ... but ONLY from your home IP
  }

  # Who may use kubectl: "access entries" in the EKS API (not the old aws-auth ConfigMap).
  # The IAM user that creates the cluster (terraform-travelagency) becomes its admin.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # STANDARD = when the version gets old, AWS upgrades the cluster instead of moving it
  # to paid Extended Support (0.60 $/hour instead of 0.10). Like "extended support disabled" for RDS.
  upgrade_policy {
    support_type = "STANDARD"
  }

  # EKS installs the basic system parts itself: VPC CNI (network of pods), kube-proxy, CoreDNS.

  tags = { Name = var.cluster_name }

  # The role must have its policy BEFORE EKS starts, and keep it until EKS is deleted
  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# Managed node group = EKS makes and updates the EC2 nodes for us (an Auto Scaling group inside).
resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = [for s in aws_subnet.public : s.id] # nodes in both zones

  ami_type       = "AL2023_x86_64_STANDARD" # Amazon Linux 2023, made for EKS by AWS
  capacity_type  = var.node_capacity_type   # SPOT or ON_DEMAND
  instance_types = var.node_instance_types
  disk_size      = var.node_disk_size

  scaling_config {
    desired_size = var.node_count
    min_size     = var.node_count
    max_size     = var.node_count + 1 # +1 so EKS can start a new node first when it updates them
  }

  update_config {
    max_unavailable = 1 # update the nodes one by one
  }

  labels = {
    project = "travelagency"
  }

  tags = { Name = "travelagency-eks-node" }

  # The node role must have all 3 policies before the nodes start (and until they are deleted)
  depends_on = [aws_iam_role_policy_attachment.nodes]
}

# metrics-server: CPU/RAM of pods for "kubectl top" and the HorizontalPodAutoscaler.
# A "community add-on": EKS installs and updates it, the code is the normal kubernetes-sigs project.
resource "aws_eks_addon" "metrics_server" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "metrics-server"

  # it runs as a pod, so it needs nodes first
  depends_on = [aws_eks_node_group.default]
}