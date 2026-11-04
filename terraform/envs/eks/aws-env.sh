# Gives THIS terminal the AWS key of terraform-travelagency from Vault, for the aws CLI and kubectl.
# Use:  source terraform/envs/eks/aws-env.sh      (source, not ./ : the variables must stay in your shell)
# The key lives only in the memory of this terminal: close it, and the key is gone. Nothing is written to disk.
# Terraform does not need this file: it reads the key from Vault itself (providers.tf).

if ! vault token lookup >/dev/null 2>&1; then
  echo "Vault: not logged in. Run: vault login -method=userpass username=nazariy" >&2
  return 1
fi

AWS_ACCESS_KEY_ID="$(vault kv get -mount=secret -field=access_key_id travelagency/aws)"
AWS_SECRET_ACCESS_KEY="$(vault kv get -mount=secret -field=secret_access_key travelagency/aws)"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
export AWS_REGION=eu-central-1

echo "AWS key for $(aws sts get-caller-identity --query Arn --output text) is set in this terminal."