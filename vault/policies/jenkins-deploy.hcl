# Policy "jenkins-deploy": for Jenkins (AppRole "jenkins-deploy").
# The Deploy stage runs app.yml, it needs only db_password and redis_password.
# Read only, only this one path. Grafana, Telegram, Proxmox secrets are NOT readable.
path "secret/data/travelagency/app" {
  capabilities = ["read"]
}