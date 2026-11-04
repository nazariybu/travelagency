# What changes most often. Everything else: defaults in variables.tf.

# true = anyone can open the site (for a demo to other people). false = only your home IP.
site_open_to_world = false

# Spot = cheap spare servers. If "terraform apply" waits a long time for the nodes and the console says
# "no Spot capacity", change to "ON_DEMAND" (about 0.05 $/hour more for both nodes).
node_capacity_type = "SPOT"
node_count         = 2