# What exists in AWS. Terraform makes AWS look like this file.
# Names start with "aws-", so they never mix with the home servers (vm-app ...).
# The IPs copy the home ones (.101 app, .105 app2, .107 redis), only in the AWS network 10.20.x.x.
#   add a line    -> terraform apply creates the server
#   delete a line -> terraform apply DELETES the server
#
# Free Tier: 750 hours of t3.micro per month for ALL servers together (3 servers = ~10 days a month free)
# and 30 GB of disk: 10 + 10 + 8 = 28 GB.
#
# There is no line for the database: it is RDS (database.tf), not a server we manage.

servers = {
  "aws-app1"  = { ip = "10.20.1.101", zone = "a", group = "app", disk = 10, swap = 2048 }
  "aws-app2"  = { ip = "10.20.2.105", zone = "b", group = "app", disk = 10, swap = 2048 }
  "aws-redis" = { ip = "10.20.1.107", zone = "a", group = "redis" }
}

# true = anyone can open the site (for a demo to other people). false = only your home IP.
site_open_to_world = false