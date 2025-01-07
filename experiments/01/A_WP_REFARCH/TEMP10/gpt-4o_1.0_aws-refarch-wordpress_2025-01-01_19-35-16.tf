terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  required_version = ">= 1.0.0"
}

provider "aws" {
  region = "us-east-1"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidr" {
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "admin_ssh_ip" {
  description = "The IP address range that is allowed SSH access to the EC2 instances"
  default     = "0.0.0.0/0"
}

# Networking
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

resource "aws_subnet" "public" {
  count                  = 2
  vpc_id                 = aws_vpc.wordpress_vpc.id
  cidr_block             = element(var.public_subnet_cidr, count.index)
  availability_zone      = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name = "WordPressPublicSubnet-${count.index}"
  }
}

resource "aws_subnet" "private" {
  count                  = 2
  vpc_id                 = aws_vpc.wordpress_vpc.id
  cidr_block             = element(var.private_subnet_cidr, count.index)
  availability_zone      = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "WordPressPrivateSubnet-${count.index}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name = "WordPressPublicRT"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security Groups
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
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ssh_ip]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "WordPressWebSG"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "WordPressDBSG"
  }
}

# Compute - EC2 Instances for WordPress
resource "aws_launch_template" "wordpress_lt" {
  name_prefix = "wordpress-instance"
  instance_type = "t2.micro"
  image_id = data.aws_ami.amazon_linux.id

  key_name = aws_key_pair.wordpress_keypair.key_name

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web_sg.id]
  }

  user_data = base64encode(data.template_file.user_data.rendered)

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  desired_capacity    = 1
  max_size            = 3
  min_size            = 1
  vpc_zone_identifier = aws_subnet.public[*].id
  launch_template     = {
    id      = aws_launch_template.wordpress_lt.id
    version = "$Latest"
  }
  lifecycle {
    create_before_destroy = true
  }
  tags = [
    {
      key                 = "Name"
      value               = "WordPressInstance"
      propagate_at_launch = true
    }
  ]
}

data "aws_default_vpc" "default" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# RDS for WordPress Database
resource "aws_db_instance" "wordpress_db" {
  allocated_storage       = 20
  max_allocated_storage   = 100
  engine                  = "mysql"
  instance_class          = "db.t2.small"
  name                    = "wordpressdb"
  username                = "admin"
  password                = "password"
  parameter_group_name    = "default.mysql8.0"
  skip_final_snapshot     = true
  multi_az                = true
  vpc_security_group_ids  = [aws_security_group.db_sg.id]
  tags = {
    Name = "WordPressDB"
  }
}

# Elastic Load Balancer
resource "aws_lb" "wordpress_alb" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = aws_subnet.public[*].id
  tags = {
    Name = "WordPressALB"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = 80
  protocol          = "HTTP"

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
  }
}

resource "aws_lb_target_group_attachment" "asg" {
  count            = 1
  target_group_arn = aws_lb_target_group.wordpress_tg.arn
  target_id        = element(aws_autoscaling_group.wordpress_asg.instance_ids, count.index)
  port             = 80
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_lb.wordpress_alb.dns_name
    origin_id   = "ALBWordPress"

    # Customize the S3 bucket origin if needed
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ALBWordPress"
    
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "WordPressCloudFront"
  }
}

# S3 Bucket for Static Assets
resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${random_string.bucket_suffix.result}"
  acl    = "public-read"

  policy = data.aws_iam_policy_document.wordpress_assets.json

  tags = {
    Name = "WordPressAssets"
  }
}

resource "aws_s3_bucket_public_access_block" "wordpress_assets" {
  bucket = aws_s3_bucket.wordpress_assets.id
  
  block_public_acls   = false
  block_public_policy = false
}

resource "random_string" "bucket_suffix" {
  length  = 6
  special = false
}

data "aws_iam_policy_document" "wordpress_assets" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.wordpress_assets.arn}/*"]
    principals {
      type = "AWS"
      identifiers = ["*"]
    }
  }
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com" # Replace with your domain
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "www.example.com" # Replace with your subdomain
  type    = "A"

  alias {
    name                   = aws_lb.wordpress_alb.dns_name
    zone_id                = aws_lb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_key_pair" "wordpress_keypair" {
  key_name   = "wordpress-keypair"
  public_key = file("~/.ssh/id_rsa.pub")
}

data "template_file" "user_data" {
  template = file("${path.module}/user_data.sh")
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.wordpress_vpc.id
}

output "public_alb_dns" {
  description = "The DNS name of the public ALB"
  value       = aws_lb.wordpress_alb.dns_name
}

output "cloudfront_domain_name" {
  description = "The domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.wordpress_cf.domain_name
}

output "db_instance_endpoint" {
  description = "The endpoint of the RDS instance"
  value       = aws_db_instance.wordpress_db.endpoint
}

output "s3_bucket_name" {
  description = "The name of the S3 bucket for static assets"
  value       = aws_s3_bucket.wordpress_assets.bucket
}
