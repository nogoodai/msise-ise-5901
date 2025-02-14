# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
}

# VPC Configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Public Subnet
resource "aws_subnet" "wordpress_public_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name        = "WordPressPublicSubnet"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Private Subnet
resource "aws_subnet" "wordpress_private_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name        = "WordPressPrivateSubnet"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Public Route Table
resource "aws_route_table" "wordpress_public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressPublicRouteTable"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Private Route Table
resource "aws_route_table" "wordpress_private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressPrivateRouteTable"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Route Table Association
resource "aws_route_table_association" "wordpress_public_route_table_association" {
  subnet_id      = aws_subnet.wordpress_public_subnet.id
  route_table_id = aws_route_table.wordpress_public_route_table.id
}

resource "aws_route_table_association" "wordpress_private_route_table_association" {
  subnet_id      = aws_subnet.wordpress_private_subnet.id
  route_table_id = aws_route_table.wordpress_private_route_table.id
}

# Public Route
resource "aws_route" "wordpress_public_route" {
  route_table_id         = aws_route_table.wordpress_public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Security Groups
resource "aws_security_group" "wordpress_web_server_sg" {
  name        = "WordPressWebServerSG"
  description = "Security group for WordPress web servers"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS traffic"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["your_ip_address/32"] # replace with your IP address
    description = "Allow SSH traffic"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outgoing traffic"
  }

  tags = {
    Name        = "WordPressWebServerSG"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_security_group" "wordpress_rds_sg" {
  name        = "WordPressRDSSG"
  description = "Security group for WordPress RDS"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_web_server_sg.id]
    description     = "Allow traffic from web servers"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outgoing traffic"
  }

  tags = {
    Name        = "WordPressRDSSG"
    Environment = "production"
    Project     = "wordpress"
  }
}

# EC2 Instances
resource "aws_instance" "wordpress_web_server" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  vpc_security_group_ids = [
    aws_security_group.wordpress_web_server_sg.id
  ]
  subnet_id = aws_subnet.wordpress_public_subnet.id
  key_name               = "wordpress"
  user_data = file("${path.module}/user_data.sh")
  monitoring              = true
  ebs_optimized           = true
  tags = {
    Name        = "WordPressWebServer"
    Environment = "production"
    Project     = "wordpress"
  }
}

# RDS Instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = "db.t2.micro"
  name                 = "wordpressdb"
  username             = var.rds_username
  password             = var.rds_password
  parameter_group_name = "default.mysql8.0"
  vpc_security_group_ids = [
    aws_security_group.wordpress_rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  storage_encrypted    = true
  backup_retention_period = 12
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]
  iam_database_authentication_enabled = true
  tags = {
    Name        = "WordPressRDS"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress_db_subnet_group"
  subnet_ids = [
    aws_subnet.wordpress_private_subnet.id
  ]
  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Elastic Load Balancer
resource "aws_lb" "wordpress_elb" {
  name               = "WordPressELB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.wordpress_web_server_sg.id]
  subnets            = [aws_subnet.wordpress_public_subnet.id]
  enable_deletion_protection = true
  drop_invalid_header_fields = true
  tags = {
    Name        = "WordPressELB"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_lb_target_group" "wordpress_elb_target_group" {
  name     = "WordPressELBTargetGroup"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressELBTargetGroup"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_lb_listener" "wordpress_elb_listener" {
  load_balancer_arn = aws_lb.wordpress_elb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_elb_target_group.arn
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_autoscaling_group" {
  name                      = "WordPressAutoScalingGroup"
  max_size                  = 5
  min_size                  = 1
  vpc_zone_identifier       = [aws_subnet.wordpress_public_subnet.id]
  launch_configuration_name = aws_launch_configuration.wordpress_launch_configuration.name
  target_group_arns        = [aws_lb_target_group.wordpress_elb_target_group.arn]
  tags = {
    Name        = "WordPressAutoScalingGroup"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name          = "WordPressLaunchConfiguration"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  security_groups = [
    aws_security_group.wordpress_web_server_sg.id
  ]
  key_name               = "wordpress"
  user_data = file("${path.module}/user_data.sh")
  lifecycle {
    create_before_destroy = true
  }
  ebs_optimized = true
  monitoring = true
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cloudfront_distribution" {
  origin {
    domain_name = aws_lb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }

  enabled = true

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

    viewer_protocol_policy = "redirect-to-https"
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
  }

  logging_config {
    bucket = aws_s3_bucket.wordpress_s3_bucket.id
    prefix = "/logs"
  }
  tags = {
    Name        = "WordPressCloudFrontDistribution"
    Environment = "production"
    Project     = "wordpress"
  }
}

# S3 Bucket
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = "wordpress-s3-bucket"
  acl    = "private"
  versioning {
    enabled = true
  }
  logging {
    target_bucket = aws_s3_bucket.wordpress_s3_bucket.id
    target_prefix = "/logs/"
  }
  tags = {
    Name        = "WordPressS3Bucket"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress_route53_zone" {
  name = "example.com"
  tags = {
    Name        = "WordPressRoute53Zone"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cloudfront_distribution.zone_id
    evaluate_target_health = false
  }
}

output "wordpress_vpc_id" {
  value = aws_vpc.wordpress_vpc.id
  description = "The ID of the WordPress VPC"
}

output "wordpress_elb_dns_name" {
  value = aws_lb.wordpress_elb.dns_name
  description = "The DNS name of the WordPress ELB"
}

output "wordpress_cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
  description = "The domain name of the WordPress CloudFront distribution"
}

output "wordpress_rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
  description = "The endpoint of the WordPress RDS instance"
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3_bucket.bucket
  description = "The name of the WordPress S3 bucket"
}

variable "rds_username" {
  type        = string
  sensitive   = true
  description = "The username for the RDS instance"
}

variable "rds_password" {
  type        = string
  sensitive   = true
  description = "The password for the RDS instance"
}
