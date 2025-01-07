# Terraform Block
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Provider configuration
provider "aws" {
  region = "us-west-2"
}

# Variables
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "Availability zones for resources"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for EC2 instances"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Instance class for RDS instance"
}

variable "cloudfront_ssl_certificate" {
  type        = string
  default     = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  description = "SSL certificate ARN for CloudFront"
}

variable "route_53_zone_name" {
  type        = string
  default     = "example.com"
  description = "Route 53 hosted zone name"
}

# Networking Resources
resource "aws_vpc" "word_press_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.word_press_vpc.id
  tags = {
    Name = "WordPressInternetGateway"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.word_press_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  tags = {
    Name = "WordPressPublicRouteTable"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.word_press_vpc.id

  tags = {
    Name = "WordPressPrivateRouteTable"
  }
}

resource "aws_subnet" "public_subnets" {
  count             = 3
  vpc_id            = aws_vpc.word_press_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "WordPressPublicSubnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = 3
  vpc_id            = aws_vpc.word_press_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 3)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "WordPressPrivateSubnet-${count.index + 1}"
  }
}

resource "aws_route_table_association" "public_route_table_association" {
  count          = 3
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_route_table_association" {
  count          = 3
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security Groups
resource "aws_security_group" "web_server_security_group" {
  name        = "WordPressWebServerSecurityGroup"
  description = "Security group for WordPress web servers"
  vpc_id      = aws_vpc.word_press_vpc.id

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
    cidr_blocks = ["192.168.1.0/24"] # Replace with your administrative IP range
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WordPressWebServerSecurityGroup"
  }
}

resource "aws_security_group" "rds_security_group" {
  name        = "WordPressRDSSecurityGroup"
  description = "Security group for WordPress RDS instance"
  vpc_id      = aws_vpc.word_press_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server_security_group.id]
  }

  tags = {
    Name = "WordPressRDSSecurityGroup"
  }
}

# EC2 Instances
resource "aws_instance" "web_servers" {
  count         = 3
  ami           = "ami-0c55b159cbfafe1f0" # Replace with your preferred AMI
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.web_server_security_group.id
  ]
  subnet_id = aws_subnet.public_subnets[count.index].id
  key_name               = "your-ssh-key" # Replace with your SSH key
  tags = {
    Name = "WordPressWebServer-${count.index + 1}"
  }
}

# RDS Instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = var.rds_instance_class
  name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = "wordpresspassword"
  vpc_security_group_ids = [
    aws_security_group.rds_security_group.id
  ]
  db_subnet_group_name    = aws_db_subnet_group.rds_subnet_group.name
  multi_az                = true
  skip_final_snapshot      = true
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = [for subnet in aws_subnet.private_subnets : subnet.id]

  tags = {
    Name = "WordPressRDSSubnetGroup"
  }
}

# Elastic Load Balancer
resource "aws_alb" "wordpress_alb" {
  name            = "wordpress-alb"
  subnets         = [for subnet in aws_subnet.public_subnets : subnet.id]
  security_groups = [aws_security_group.web_server_security_group.id]
  tags = {
    Name = "WordPressALB"
  }
}

resource "aws_alb_listener" "wordpress_alb_listener" {
  load_balancer_arn = aws_alb.wordpress_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.wordpress_alb_target_group.arn
    type             = "forward"
  }
}

resource "aws_alb_target_group" "wordpress_alb_target_group" {
  name     = "wordpress-alb-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.word_press_vpc.id
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_autoscaling_group" {
  name                = "wordpress-autoscaling-group"
  max_size            = 3
  min_size            = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity        = 1
  launch_configuration      = aws_launch_configuration.wordpress_launch_configuration.name
  vpc_zone_identifier       = [for subnet in aws_subnet.public_subnets : subnet.id]
}

resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name          = "wordpress-launch-configuration"
  image_id      = "ami-0c55b159cbfafe1f0" # Replace with your preferred AMI
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.web_server_security_group.id
  ]
  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  enabled = true

  alias {
    name = "example.com" # Replace with your domain
    ssl_certificates {
      acm_certificate_arn = var.cloudfront_ssl_certificate
    }
  }

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-alb"

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

  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = "wordpress-alb"
  }

  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = var.cloudfront_ssl_certificate
    ssl_support_method  = "sni-only"
  }
}

# S3 Bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "example.com" # Replace with your bucket name
  acl    = "private"

  tags = {
    Name = "WordPressS3Bucket"
  }
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress_zone" {
  name = var.route_53_zone_name
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = var.route_53_zone_name
  type    = "A"

  alias {
    name                   = aws_alb.wordpress_alb.dns_name
    zone_id               = aws_alb.wordpress_alb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "wordpress_cloudfront_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "www.example.com" # Replace with your subdomain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_distribution.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_distribution.zone_id
    evaluate_target_health = false
  }
}

output "alb_dns_name" {
  value = aws_alb.wordpress_alb.dns_name
}

output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_distribution.domain_name
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_bucket.id
}

output "wordpress_rds_instance_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "wordpress_rds_instance_password" {
  value = aws_db_instance.wordpress_rds.password
  sensitive = true
}
