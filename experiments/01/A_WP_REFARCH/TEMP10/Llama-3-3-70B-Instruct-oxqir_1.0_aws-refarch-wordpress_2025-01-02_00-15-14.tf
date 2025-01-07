provider "aws" {
  region = "us-west-2"
  required_providers {
    aws = "= 5.1.0"
  }
}

# VPC Configuration
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  default = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

# Subnets
resource "aws_subnet" "public_subnet" {
  count             = length(var.availability_zones)
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  vpc_id            = aws_vpc.wordpress_vpc.id
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PublicSubnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnet" {
  count             = length(var.availability_zones)
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, length(var.availability_zones) + count.index)
  vpc_id            = aws_vpc.wordpress_vpc.id
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PrivateSubnet-${count.index + 1}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Route Tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table_association" "public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security Groups
variable "allowed_ssh_cidr_blocks" {
  default = ["0.0.0.0/0"]
}

resource "aws_security_group" "wordpress_sg" {
  name        = "WordPressSG"
  description = "Security Group for WordPress EC2 instances"
  vpc_id      = aws_vpc.wordpress_vpc.id

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
    cidr_blocks = var.allowed_ssh_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "RDSSG"
  description = "Security Group for RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "elb_sg" {
  name        = "ELBSG"
  description = "Security Group for ELB"
  vpc_id      = aws_vpc.wordpress_vpc.id

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
}

# EC2 Instances
variable "instance_type" {
  default = "t2.micro"
}

variable "ami_id" {
  default = "ami-0c949fcb3b09b4776"
}

resource "aws_launch_configuration" "wordpress_launch_config" {
  name        = "WordPressLaunchConfig"
  image_id    = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.wordpress_sg.id]
  user_data = file("${path.module}/user_data.sh")

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  name             = "WordPressASG"
  launch_configuration = aws_launch_configuration.wordpress_launch_config.name
  vpc_zone_identifier  = aws_subnet.public_subnet.*.id
  desired_capacity   = 2
  min_size           = 1
  max_size           = 5

  tag {
    key                 = "Name"
    value               = "WordPressASG"
    propagate_at_launch = true
  }
}

# RDS Instance
variable "rds_instance_type" {
  default = "db.t2.small"
}

variable "rds_database_name" {
  default = "wordpressdb"
}

variable "rds_master_username" {
  default = "wordpressuser"
}

variable "rds_master_password" {
  default = "wordpresspass"
}

resource "aws_db_instance" "wordpress_rds" {
  identifier        = "wordpress-rds"
  instance_class    = var.rds_instance_type
  engine            = "mysql"
  name              = var.rds_database_name
  username          = var.rds_master_username
  password          = var.rds_master_password
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  multi_az          = true
  publicly_accessible = false
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = aws_subnet.public_subnet.*.id
  security_groups = [aws_security_group.elb_sg.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  listener {
    instance_port     = 443
    instance_protocol = "https"
    lb_port           = 443
    lb_protocol       = "https"
    ssl_certificate_id = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  }

  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 10
    timeout             = 5
    target              = "HTTP:80/"
    interval            = 30
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }

  enabled     = true
  is_ipv6_enabled = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-elb"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# S3 Bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-bucket"
  acl    = "private"

  versioning {
    enabled = true
  }

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET", "DELETE"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

# Route 53
resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "wordpress_cloudfront_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "cdn.example.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_distribution.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_distribution.zone_id
    evaluate_target_health = false
  }
}

output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_rds_password" {
  sensitive = true
  value     = var.rds_master_password
}

output "wordpress_bucket_name" {
  value = aws_s3_bucket.wordpress_bucket.bucket
}

output "wordpress_cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.wordpress_distribution.id
}

output "wordpress_route53_zone_id" {
  value = aws_route53_zone.wordpress_zone.id
}
