# Printed after "terraform apply" and by "terraform output".

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.this.name
}

output "kubernetes_version" {
  description = "Kubernetes version of the control plane"
  value       = aws_eks_cluster.this.version
}

output "kubectl_config_command" {
  description = "Run it once after apply: writes the cluster to ~/.kube/config"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.this.name}"
}

output "db_endpoint" {
  description = "RDS MySQL address (works only from inside the VPC)"
  value       = aws_db_instance.this.address
}

output "my_ip" {
  description = "Your home public IP: only it may use kubectl (and open the site if site_open_to_world = false)"
  value       = local.my_ip_cidr
}

output "k8s_generated_file" {
  description = "Kubernetes file written by Terraform"
  value       = abspath(local_file.k8s_aws.filename)
}