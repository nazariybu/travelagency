# Application Load Balancer (ALB): does the job of vm-lb (nginx) at home.
# It has a public DNS name, sends every request to a healthy app node (round-robin),
# and checks /form-login on every node every 15 seconds. Sessions are in Redis, so no sticky sessions.

resource "aws_lb" "this" {
  name               = "travelagency"
  load_balancer_type = "application"
  internal           = false # has a public address
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.public : s.id] # ALB needs at least 2 zones

  drop_invalid_header_fields = true

  tags = { Name = "travelagency" }
}

# Target group = the list of app nodes behind the load balancer (like "upstream" in nginx)
resource "aws_lb_target_group" "app" {
  name        = "travelagency-app"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this.id
  target_type = "instance"

  deregistration_delay = 30 # seconds to finish open requests when a node is removed

  health_check {
    path                = "/form-login" # the same page app.yml waits for
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2 # 2 good checks in a row = node gets traffic
    unhealthy_threshold = 3 # 3 bad checks in a row = no traffic to this node
  }

  tags = { Name = "travelagency-app" }
}

# Put every server of the group "app" into the target group
resource "aws_lb_target_group_attachment" "app" {
  for_each = { for name, s in var.servers : name => s if s.group == "app" }

  target_group_arn = aws_lb_target_group.app.arn
  target_id        = module.server[each.key].id
  port             = var.app_port
}

# Listen on port 80 and forward everything to the app nodes.
# HTTPS needs a domain name for the certificate (ACM): see REPORT.md, "Next".
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = { Name = "travelagency-http" }
}