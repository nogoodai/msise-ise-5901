terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 0.14"
}

provider "aws" {
  region = "us-east-1"
}

###################
# Networking
###################

# VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "WordPressVPC"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Subnets
resource "aws_subnet" "wordpress_public_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.wordpress_vpc.id
  map_public_ip_on_launch = true
  cidr_block              = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 4, count.index)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "WordPressPublicSubnet-${count.index}"
  }
}

resource "aws_subnet" "wordpress_private_subnet" {
  count             = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 4, count.index + 2)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "WordPressPrivateSubnet-${count.index}"
  }
}

# Route Tables
resource "aws_route_table" "wordpress_public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name = "WordPressPublicRT"
  }
}

resource "aws_route_table_association" "public_subnet_assoc" {
  count          = 2
  subnet_id      = element(aws_subnet.wordpress_public_subnet.*.id, count.index)
  route_table_id = aws_route_table.wordpress_public_rt.id
}

resource "aws_nat_gateway" "wordpress_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.wordpress_public_subnet[0].id
}

resource "aws_route_table" "wordpress_private_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.wordpress_nat.id
  }
  tags = {
    Name = "WordPressPrivateRT"
  }
}

resource "aws_route_table_association" "private_subnet_assoc" {
  count          = 2
  subnet_id      = element(aws_subnet.wordpress_private_subnet.*.id, count.index)
  route_table_id = aws_route_table.wordpress_private_rt.id
}

# Elastic IP for NAT
resource "aws_eip" "nat_eip" {
  vpc = true
}

###################
# Security Groups
###################

# Security Group for Web Server
resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WebServerSG"
  }
}

# Security Group for RDS
resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "DatabaseSG"
  }
}

###################
# EC2 Bastion Host
###################

resource "aws_instance" "bastion" {
  ami                         = "ami-0d5eff06f840b45e9" # Change to preferred AMI
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.wordpress_public_subnet[0].id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.bastion_key.key_name

  security_groups = [
    aws_security_group.web_sg.id
  ]

  tags = {
    Name = "BastionHost"
  }
}

resource "aws_key_pair" "bastion_key" {
  key_name   = "bastion-key"
  public_key = file("~/.ssh/bastion.pub") # Change to your public key location
}

###################
# EFS Configuration
###################

resource "aws_efs_file_system" "wordpress_efs" {
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name = "WordPressEFS"
  }
}

resource "aws_efs_mount_target" "wordpress_efs_target" {
  count          = 2
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = element(aws_subnet.wordpress_private_subnet.*.id, count.index)
  
  security_groups = [
    aws_security_group.web_sg.id
  ]
}

###################
# EC2 for WordPress
###################

resource "aws_launch_configuration" "wordpress_launch_config" {
  name_prefix   = "wordpress-lc-"
  image_id      = "ami-0d5eff06f840b45e9" # Update with preferred AMI
  instance_type = "t2.micro"
  key_name      = aws_key_pair.bastion_key.key_name

  security_groups = [
    aws_security_group.web_sg.id
  ]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd mysql php php-mysql
              service httpd start
              chkconfig httpd on
              EOF
}

resource "aws_autoscaling_group" "wordpress_asg" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.wordpress_private_subnet.*.id
  launch_configuration = aws_launch_configuration.wordpress_launch_config.id
  tag {
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }
}

###################
# RDS for WordPress
###################

resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.small"
  name                 = "wordpressdb"
  username             = "admin"
  password             = "adminpassword" # Change to a secure password
  parameter_group_name = "default.mysql5.7"
  multi_az             = true
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot  = true

  tags = {
    Name = "WordPressRDS"
  }
}

###################
# ALB Configuration
###################

resource "aws_lb" "wordpress_alb" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = aws_subnet.wordpress_public_subnet.*.id

  enable_deletion_protection = true

  tags = {
    Name = "WordPressALB"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:us-east-1:123456789012:certificate/abcd-1234-abcd-1234-abcd1234abcd" # Change to your certificate ARN
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

resource "aws_lb_target_group" "wordpress_tg" {
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 2
    matcher             = "200-299"
  }
}

resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.wordpress_asg.id
  alb_target_group_arn   = aws_lb_target_group.wordpress_tg.arn
}

###################
# CloudFront Configuration
###################

resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_lb.wordpress_alb.dns_name
    origin_id   = "wordpress-alb"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for WordPress"
  default_root_object = "index.html"

  default_cache_behavior {
    target_origin_id = "wordpress-alb"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  tags = {
    Name = "WordPressDistribution"
  }
}

###################
# S3 for Assets
###################

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-example" # Change to a unique bucket name

  acl = "public-read"

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }

  tags = {
    Name = "WordPressAssets"
  }
}

###################
# Route 53 DNS
###################

resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com" # Change to your domain
}

resource "aws_route53_record" "wordpress_alb_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "www"
  type    = "A"
  alias {
    name                   = aws_lb.wordpress_alb.dns_name
    zone_id                = aws_lb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "wordpress_cname_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "cdn"
  type    = "CNAME"
  ttl     = "300"
  records = [aws_cloudfront_distribution.wordpress_distribution.domain_name]
}

###################
# Outputs
###################

output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "public_subnet_ids" {
  value = aws_subnet.wordpress_public_subnet.*.id
}

output "private_subnet_ids" {
  value = aws_subnet.wordpress_private_subnet.*.id
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "wordpress_rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "alb_dns_name" {
  value = aws_lb.wordpress_alb.dns_name
}

output "cloudfront_distribution_url" {
  value = aws_cloudfront_distribution.wordpress_distribution.domain_name
}
