# Policy "travelagency-admin": for a person (user "nazariy", userpass login).
# Read, add, change and delete all TravelAgency secrets. Nothing else in Vault.
# Ansible on the ansible host runs with this person's token.

# KV v2 keeps the values under secret/data/...
path "secret/data/travelagency/*" {
  capabilities = ["create", "read", "update", "patch", "delete"]
}

# ... and the list of keys and versions under secret/metadata/...
path "secret/metadata/travelagency/*" {
  capabilities = ["read", "list", "delete"]
}

path "secret/metadata/travelagency" {
  capabilities = ["list"]
}