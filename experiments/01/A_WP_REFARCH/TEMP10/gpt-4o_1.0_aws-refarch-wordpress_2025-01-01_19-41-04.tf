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

variable "public_subnets" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  type    = list(string)
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "instance_type" {
  default = "t2.micro"
}

variable "key_name" {
  description = "SSH key pair name for bastion and EC2 instances"
  default     = "wordpress-key"
}

variable "db_instance_class" {
  description = "RDS instance class"
  default     = "db.t2.small"
}

variable "db_name" {
  default = "wordpress"
}

variable "db_username" {
  default = "admin"
}

variable "db_password" {
  default = "password"
  sensitive = true
}

data "aws_ami" "latest_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "wordpress-igw"
  }
}

resource "aws_subnet" "public" {
  count             = length(var.public_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.public_subnets, count.index)
  map_public_ip_on_launch = true
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name = "wordpress-public-${count.index}"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.private_subnets, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name = "wordpress-private-${count.index}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "wordpress-public-rt"
  }
}

resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = element(aws_subnet.public[*].id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.main.id
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
    cidr_blocks = ["your_ip/cidr"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress-web-sg"
  }
}

// EC2 instances (WordPress hosted)
resource "aws_launch_configuration" "wordpress_lc" {
  name_prefix          = "wordpress-lc-"
  image_id             = data.aws_ami.latest_linux.id
  instance_type        = var.instance_type
  key_name             = var.key_name
  security_groups      = [aws_security_group.web_sg.id]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.public[*].id
  launch_configuration = aws_launch_configuration.wordpress_lc.id

  tag {
    key                 = "Name"
    value               = "wordpress-asg-instance"
    propagate_at_launch = true
  }

  // Load balancer
  target_group_arns = [aws_lb_target_group.wordpress_tg.arn]
}

resource "aws_lb" "wordpress_alb" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.web_sg.id]

  enable_deletion_protection = true

  tags = {
    Name = "wordpress-alb"
  }
}

resource "aws_lb_target_group" "wordpress_tg" {
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    interval            = 30
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
    healthy_threshold   = 5
  }
}

resource "aws_lb_listener" "wordpress_http" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

// RDS for WordPress
resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = var.db_instance_class
  name                 = var.db_name
  username             = var.db_username
  password             = var.db_password
  parameter_group_name = "default.mysql8.0"
  multi_az             = true
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  skip_final_snapshot  = true

  tags = {
    Name = "wordpress-db"
  }
}

// CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_domain_name
    origin_id   = "wordpress-s3-origin"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_cache_behavior {
    target_origin_id = "wordpress-s3-origin"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    compress               = true
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "wordpress-distribution"
  }
}

// S3 Bucket for assets
resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-bucket"

  tags = {
    Name = "wordpress-assets"
  }
}

resource "aws_s3_bucket_policy" "wordpress_assets_policy" {
  bucket = aws_s3_bucket.wordpress_assets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "s3:GetObject"
      Effect    = "Allow"
      Resource  = "${aws_s3_bucket.wordpress_assets.arn}/*"
      Principal = "*"
    }]
  })
}

// Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress_zone" {
  name = "yourdomain.com"
}

resource "aws_route53_record" "wordpress_alb" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "wordpress"
  type    = "A"
  alias {
    name                   = aws_lb.wordpress_alb.dns_name
    zone_id                = aws_lb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

// Output Values
output "vpc_id" {
  value = aws_vpc.main.id
}

output "subnets" {
  value = {
    public  = aws_subnet.public[*].id
    private = aws_subnet.private[*].id
  }
}

output "alb_dns_name" {
  value = aws_lb.wordpress_alb.dns_name
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}

output "s3_bucket_domain_name" {
  value = aws_s3_bucket.wordpress_assets.bucket_domain_name
}

output "cloudfront_url" {
  value = aws_cloudfront_distribution.wordpress_distribution.domain_name
}
