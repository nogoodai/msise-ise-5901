# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0.0"
    }
  }
  required_version = ">= 1.2.0"
}

# Provider configuration for AWS
provider "aws" {
  region = var.region
}

# Variables
variable "region" {
  type        = string
  default     = "us-west-2"
  description = "AWS Region"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "VPC CIDR block"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "Availability zones"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "EC2 instance type"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "RDS instance class"
}

variable "cloudfront_domain" {
  type        = string
  default     = "example.com"
  description = "CloudFront domain"
}

variable "route53_domain" {
  type        = string
  default     = "example.com"
  description = "Route 53 domain"
}

variable "ssh_key_name" {
  type        = string
  default     = "ssh-key"
  description = "SSH key name"
}

# VPC and networking resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_subnet" "public_subnets" {
  count             = length(var.availability_zones)
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicSubnet-${count.index + 1}"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.availability_zones)
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, length(var.availability_zones) + count.index)
  availability_zone = var.availability_zones[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateSubnet-${count.index + 1}"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name        = "PublicRouteTable"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route_table_association" "public_subnets_association" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnets_association" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security groups
resource "aws_security_group" "wordpress_sg" {
  name        = "WordPressSG"
  description = "Security group for WordPress instances"
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
    Name        = "WordPressSG"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "RDSSG"
  description = "Security group for RDS instances"
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
  tags = {
    Name        = "RDSSG"
    Environment = "production"
    Project     = "wordpress"
  }
}

# EC2 instances for WordPress
resource "aws_instance" "wordpress_instance" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.wordpress_sg.id
  ]
  subnet_id = aws_subnet.public_subnets[0].id
  key_name               = var.ssh_key_name
  tags = {
    Name        = "WordPressInstance"
    Environment = "production"
    Project     = "wordpress"
  }
}

# RDS instance for WordPress database
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = var.rds_instance_class
  name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = "wordpresspassword"
  vpc_security_group_ids = [
    aws_security_group.rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  tags = {
    Name        = "WordPressRDS"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress_db_subnet_group"
  subnet_ids = aws_subnet.private_subnets[*].id
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
  security_groups    = [aws_security_group.wordpress_sg.id]
  subnets            = aws_subnet.public_subnets[*].id
  tags = {
    Name        = "WordPressELB"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_lb_listener" "wordpress_elb_listener" {
  load_balancer_arn = aws_lb.wordpress_elb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_elb_target_group.arn
  }
}

resource "aws_lb_target_group" "wordpress_elb_target_group" {
  name     = "WordPressELBTargetGroup"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressELBTargetGroup"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_lb_target_group_attachment" "wordpress_elb_target_group_attachment" {
  target_group_arn = aws_lb_target_group.wordpress_elb_target_group.arn
  target_id        = aws_instance.wordpress_instance.id
  port             = 80
}

# Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_autoscaling_group" {
  name                = "WordPressAutoScalingGroup"
  max_size            = 5
  min_size            = 1
  desired_capacity    = 1
  health_check_type   = "EC2"
  launch_configuration = aws_launch_configuration.wordpress_launch_configuration.name
  vpc_zone_identifier = aws_subnet.public_subnets[0].id
  tags = [
    {
      key                 = "Name"
      value               = "WordPressAutoScalingGroup"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = "production"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = "wordpress"
      propagate_at_launch = true
    },
  ]
}

resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name          = "WordPressLaunchConfiguration"
  image_id      = "ami-0c55b159cbfafe1f0"
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.wordpress_sg.id
  ]
  key_name = var.ssh_key_name
}

# CloudFront distribution for content delivery
resource "aws_cloudfront_distribution" "wordpress_cloudfront_distribution" {
  origin {
    domain_name = aws_s3_bucket.wordpress_s3_bucket.bucket_regional_domain_name
    origin_id   = "S3Origin"
  }
  enabled = true
  default_root_object = "index.html"
  aliases = [var.cloudfront_domain]
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"
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
    acm_certificate_arn = aws_acm_certificate.wordpress_acm_certificate.arn
    ssl_support_method  = "sni-only"
  }
  tags = {
    Name        = "WordPressCloudFrontDistribution"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = var.cloudfront_domain
  acl    = "private"
  tags = {
    Name        = "WordPressS3Bucket"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_acm_certificate" "wordpress_acm_certificate" {
  domain_name       = var.cloudfront_domain
  validation_method = "DNS"
  tags = {
    Name        = "WordPressACMCertificate"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route53_record" "wordpress_route53_record" {
  name    = var.route53_domain
  type    = "A"
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cloudfront_distribution.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "wordpress_route53_zone" {
  name = var.route53_domain
  tags = {
    Name        = "WordPressRoute53Zone"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Outputs
output "wordpress_elb_dns_name" {
  value = aws_lb.wordpress_elb.dns_name
}

output "wordpress_rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "wordpress_cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
}

output "wordpress_route53_record_name" {
  value = aws_route53_record.wordpress_route53_record.name
}
