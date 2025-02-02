terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = "us-west-2"
}

variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "Availability zones for the VPC"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for the EC2 instances"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
  description = "AMI ID for the EC2 instances"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Instance class for the RDS instance"
}

variable "rds_engine" {
  type        = string
  default     = "mysql"
  description = "Engine for the RDS instance"
}

variable "elasticache_node_type" {
  type        = string
  default     = "cache.t2.micro"
  description = "Node type for the ElastiCache cluster"
}

variable "elasticache_num_nodes" {
  type        = number
  default     = 1
  description = "Number of nodes for the ElastiCache cluster"
}

variable "cloudfront_distribution_domain_name" {
  type        = string
  default     = "example.com"
  description = "Domain name for the CloudFront distribution"
}

variable "route53_domain_name" {
  type        = string
  default     = "example.com"
  description = "Domain name for the Route 53 hosted zone"
}

# VPC and networking resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name        = "wordpress-vpc"
    Environment = "production"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "wordpress-igw"
    Environment = "production"
  }
}

resource "aws_subnet" "wordpress_public_subnet" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "wordpress-public-subnet-${count.index}"
    Environment = "production"
  }
}

resource "aws_subnet" "wordpress_private_subnet" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 8, length(var.availability_zones) + count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "wordpress-private-subnet-${count.index}"
    Environment = "production"
  }
}

resource "aws_route_table" "wordpress_public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "wordpress-public-route-table"
    Environment = "production"
  }
}

resource "aws_route" "wordpress_public_route" {
  route_table_id         = aws_route_table.wordpress_public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table_association" "wordpress_public_route_table_association" {
  count          = length(aws_subnet.wordpress_public_subnet)
  subnet_id      = aws_subnet.wordpress_public_subnet[count.index].id
  route_table_id = aws_route_table.wordpress_public_route_table.id
}

# Security groups
resource "aws_security_group" "wordpress_web_server_sg" {
  name        = "wordpress-web-server-sg"
  description = "Security group for WordPress web servers"
  vpc_id      = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "wordpress-web-server-sg"
    Environment = "production"
  }

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
}

resource "aws_security_group" "wordpress_rds_sg" {
  name        = "wordpress-rds-sg"
  description = "Security group for WordPress RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "wordpress-rds-sg"
    Environment = "production"
  }

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_web_server_sg.id]
  }
}

# EC2 instances
resource "aws_instance" "wordpress_instance" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.wordpress_web_server_sg.id
  ]
  subnet_id = aws_subnet.wordpress_private_subnet[0].id
  tags = {
    Name        = "wordpress-instance"
    Environment = "production"
  }
}

# RDS instance
resource "aws_db_instance" "wordpress_rds_instance" {
  identifier        = "wordpress-rds-instance"
  instance_class    = var.rds_instance_class
  engine            = var.rds_engine
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  vpc_security_group_ids = [
    aws_security_group.wordpress_rds_sg.id
  ]
  tags = {
    Name        = "wordpress-rds-instance"
    Environment = "production"
  }
}

resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = aws_subnet.wordpress_private_subnet[*].id
  tags = {
    Name        = "wordpress-rds-subnet-group"
    Environment = "production"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.wordpress_public_subnet[*].id
  security_groups = [aws_security_group.wordpress_web_server_sg.id]
  tags = {
    Name        = "wordpress-elb"
    Environment = "production"
  }

  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 80
    lb_protocol        = "http"
  }

  listener {
    instance_port      = 443
    instance_protocol  = "https"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = aws_subnet.wordpress_private_subnet[*].id
  tags = [
    {
      key                 = "Name"
      value               = "wordpress-asg"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = "production"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.wordpress_web_server_sg.id
  ]
  user_data = file("wordpress_user_data.sh")
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cloudfront_distribution" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases = ["${var.cloudfront_distribution_domain_name}"]

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
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "sni-only"
  }
}

# S3 bucket
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket        = var.route53_domain_name
  acl           = "private"
  force_destroy = true
  tags = {
    Name        = "wordpress-s3-bucket"
    Environment = "production"
  }
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_route53_zone" {
  name = var.route53_domain_name
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name    = var.route53_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cloudfront_distribution.zone_id
    evaluate_target_health = false
  }
}

# ElastiCache cluster
resource "aws_elasticache_cluster" "wordpress_elasticache_cluster" {
  cluster_id           = "wordpress-elasticache-cluster"
  engine               = "memcached"
  node_type            = var.elasticache_node_type
  num_cache_nodes      = var.elasticache_num_nodes
  parameter_group_name = "default.memcached1.4"
  port                 = 11211
  tags = {
    Name        = "wordpress-elasticache-cluster"
    Environment = "production"
  }
}

resource "aws_elasticache_subnet_group" "wordpress_elasticache_subnet_group" {
  name       = "wordpress-elasticache-subnet-group"
  subnet_ids = aws_subnet.wordpress_private_subnet[*].id
  tags = {
    Name        = "wordpress-elasticache-subnet-group"
    Environment = "production"
  }
}

# CloudWatch logs
resource "aws_cloudwatch_log_group" "wordpress_cloudwatch_log_group" {
  name = "wordpress-cloudwatch-log-group"
}

resource "aws_cloudwatch_log_stream" "wordpress_cloudwatch_log_stream" {
  name           = "wordpress-cloudwatch-log-stream"
  log_group_name = aws_cloudwatch_log_group.wordpress_cloudwatch_log_group.name
}

# Outputs
output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
}

output "wordpress_rds_instance_endpoint" {
  value = aws_db_instance.wordpress_rds_instance.endpoint
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3_bucket.id
}

output "wordpress_route53_zone_id" {
  value = aws_route53_zone.wordpress_route53_zone.id
}
