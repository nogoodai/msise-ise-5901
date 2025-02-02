terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = "us-west-2"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "The availability zones to use for the subnets"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "The instance type for the EC2 instances"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "The instance class for the RDS instance"
}

variable "wordpress_db_username" {
  type        = string
  sensitive   = true
  description = "The username for the WordPress database"
}

variable "wordpress_db_password" {
  type        = string
  sensitive   = true
  description = "The password for the WordPress database"
}

# VPC and networking resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
  }
}

resource "aws_subnet" "wordpress_public_subnet" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "WordPressPublicSubnet-${count.index + 1}"
    Environment = "production"
  }
}

resource "aws_subnet" "wordpress_private_subnet" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + length(var.availability_zones))
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "WordPressPrivateSubnet-${count.index + 1}"
    Environment = "production"
  }
}

resource "aws_route_table" "wordpress_public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name        = "WordPressPublicRouteTable"
    Environment = "production"
  }
}

resource "aws_route_table" "wordpress_private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressPrivateRouteTable"
    Environment = "production"
  }
}

resource "aws_route_table_association" "wordpress_public_route_table_association" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.wordpress_public_subnet[count.index].id
  route_table_id = aws_route_table.wordpress_public_route_table.id
}

resource "aws_route_table_association" "wordpress_private_route_table_association" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.wordpress_private_subnet[count.index].id
  route_table_id = aws_route_table.wordpress_private_route_table.id
}

# Security groups
resource "aws_security_group" "wordpress_ec2_security_group" {
  name        = "WordPressEC2SecurityGroup"
  description = "Allow inbound HTTP and HTTPS traffic"
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
    Environment = "production"
  }
}

resource "aws_security_group" "wordpress_rds_security_group" {
  name        = "WordPressRDSSecurityGroup"
  description = "Allow inbound MySQL traffic from WordPress EC2 instances"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_ec2_security_group.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "WordPressRDSSecurityGroup"
    Environment = "production"
  }
}

# EC2 instances
resource "aws_instance" "wordpress_ec2_instance" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.wordpress_ec2_security_group.id
  ]
  subnet_id = aws_subnet.wordpress_public_subnet[0].id
  key_name               = "wordpress-ec2-key"
  user_data              = file("${path.module}/wordpress-install.sh")
  tags = {
    Name        = "WordPressEC2Instance"
    Environment = "production"
  }
}

# RDS instance
resource "aws_db_instance" "wordpress_rds_instance" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.20"
  instance_class       = var.rds_instance_class
  name                 = "wordpressdb"
  username             = var.wordpress_db_username
  password             = var.wordpress_db_password
  vpc_security_group_ids = [
    aws_security_group.wordpress_rds_security_group.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  tags = {
    Name        = "WordPressRDSInstance"
    Environment = "production"
  }
}

resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = aws_subnet.wordpress_private_subnet[*].id
  tags = {
    Name        = "WordPressRDSSubnetGroup"
    Environment = "production"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = aws_subnet.wordpress_public_subnet[*].id
  security_groups = [aws_security_group.wordpress_ec2_security_group.id]
  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
  tags = {
    Name        = "WordPressELB"
    Environment = "production"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  launch_configuration      = aws_launch_configuration.wordpress_launch_configuration.name
  min_size                  = 1
  max_size                  = 3
  desired_capacity          = 1
  vpc_zone_identifier       = aws_subnet.wordpress_public_subnet[*].id
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  tag {
    key                 = "Name"
    value               = "WordPressEC2Instance"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name          = "WordPressLaunchConfiguration"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.wordpress_ec2_security_group.id
  ]
  key_name               = "wordpress-ec2-key"
  user_data              = file("${path.module}/wordpress-install.sh")
  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cloudfront_distribution" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = ["example.com"]
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WordPressELB"
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
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "sni-only"
  }
}

# S3 bucket
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = "example.com"
  acl    = "public-read"
  policy = file("${path.module}/s3-policy.json")
  website {
    index_document = "index.html"
    error_document = "error.html"
  }
  tags = {
    Name        = "WordPressS3Bucket"
    Environment = "production"
  }
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_route53_zone" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name    = "example.com"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cloudfront_distribution.zone_id
    evaluate_target_health = false
  }
}

output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_rds_instance_address" {
  value = aws_db_instance.wordpress_rds_instance.address
}

output "wordpress_cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
}
