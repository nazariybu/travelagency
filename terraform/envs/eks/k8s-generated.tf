# Terraform writes the part of the Kubernetes config that only Terraform knows:
# the RDS address and who may open the site. Same idea as ansible/inventory-aws.ini.
# The file is NOT in Git (.gitignore): the address and your IP are different for every apply.

resource "local_file" "k8s_aws" {
  filename        = "${path.module}/../../../k8s/05-aws-generated.yaml"
  file_permission = "0644"

  content = templatefile("${path.module}/k8s-aws.yaml.tftpl", {
    db_host     = aws_db_instance.this.address
    allow_cidrs = local.site_cidrs
  })
}