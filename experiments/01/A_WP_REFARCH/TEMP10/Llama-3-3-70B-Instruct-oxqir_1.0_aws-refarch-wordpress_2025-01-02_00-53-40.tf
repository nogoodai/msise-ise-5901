# Configure the AWS Provider
terraform {
  required_version = ">= 0.15.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Define variables for AWS provider configuration
variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region to deploy resources"
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
}

# VPC and Networking Resources
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for VPC"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "Production"
  }
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
  description = "Availability zones for subnets"
}

resource "aws_subnet" "public_subnets" {
  count = length(var.availability_zones)
  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name        = "PublicSubnet${count.index}"
    Environment = "Production"
  }
}

resource "aws_subnet" "private_subnets" {
  count = length(var.availability_zones)
  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, length(var.availability_zones) + count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PrivateSubnet${count.index}"
    Environment = "Production"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "Production"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = "Production"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_subnet_association" {
  count = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table" "private_rt" {
  count = length(var.availability_zones)
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable${count.index}"
    Environment = "Production"
  }
}

resource "aws_route_table_association" "private_subnet_association" {
  count = length(var.availability_zones)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rt[count.index].id
}

# Security Groups
resource "aws_security_group" "ec2_sg" {
  name        = "WordPressEC2SecurityGroup"
  description = "Allow HTTP, HTTPS, and SSH traffic"
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
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WordPressEC2SecurityGroup"
    Environment = "Production"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "WordPressRDSSecurityGroup"
  description = "Allow MySQL traffic from EC2 instances"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  tags = {
    Name        = "WordPressRDSSecurityGroup"
    Environment = "Production"
  }
}

resource "aws_security_group" "elb_sg" {
  name        = "WordPressELBSecurityGroup"
  description = "Allow HTTP and HTTPS traffic"
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

  tags = {
    Name        = "WordPressELBSecurityGroup"
    Environment = "Production"
  }
}

# EC2 Instances for WordPress
resource "aws_instance" "wordpress" {
  count = 2
  ami           = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id = aws_subnet.public_subnets[count.index].id
  key_name = "wordpress-key"
  tags = {
    Name        = "WordPressInstance${count.index}"
    Environment = "Production"
  }
}

# RDS Instance for WordPress Database
resource "aws_db_instance" "wordpress_db" {
  identifier        = "wordpress-db"
  instance_class    = "db.t2.small"
  engine            = "mysql"
  engine_version    = "8.0.23"
  username          = "wordpress_user"
  password          = "wordpress_password"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  availability_zone = var.availability_zones[0]
  storage_type      = "gp2"
  tags = {
    Name        = "WordPressDBInstance"
    Environment = "Production"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.public_subnets.*.id
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
  }

  tags = {
    Name        = "WordPressELB"
    Environment = "Production"
  }
}

# Auto Scaling Group for EC2 Instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  launch_configuration      = "wordpress-lc"
  min_size                  = 2
  max_size                  = 5
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id
  load_balancers            = [aws_elb.wordpress_elb.name]
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  tags = {
    Name        = "WordPressASG"
    Environment = "Production"
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_s3_bucket.wordpress_bucket.bucket_regional_domain_name
    origin_id   = "wordpress-s3-origin"
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-s3-origin"

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

  tags = {
    Name        = "WordPressCFD"
    Environment = "Production"
  }
}

# S3 Bucket for Static Assets
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket        = "wordpress-static-assets"
  force_destroy = true

  tags = {
    Name        = "WordPressS3Bucket"
    Environment = "Production"
  }
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = true
  }
}

# Outputs
output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_db_instance_address" {
  value = aws_db_instance.wordpress_db.address
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_bucket.id
}

output "wordpress_cf_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cfd.domain_name
}
