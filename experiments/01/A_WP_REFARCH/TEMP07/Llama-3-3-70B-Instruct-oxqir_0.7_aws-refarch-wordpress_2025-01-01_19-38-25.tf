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

# Variables for user-configurable values
variable "vpc_cidr" {
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
  default     = "ami-0c55b159cbfafe1f0"
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

variable "elasticache_engine" {
  type        = string
  default     = "memcached"
  description = "Engine for the Elasticache cluster"
}

variable "elasticache_node_type" {
  type        = string
  default     = "cache.t2.micro"
  description = "Node type for the Elasticache cluster"
}

variable "cloudfront_origin" {
  type        = string
  default     = "alb"
  description = "Origin for the CloudFront distribution"
}

variable "route53_domain" {
  type        = string
  default     = "example.com"
  description = "Domain for the Route 53 hosted zone"
}

# VPC and networking resources
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

resource "aws_subnet" "wordpress_public_subnet" {
  count             = 3
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "WordPressPublicSubnet${count.index + 1}"
  }
}

resource "aws_subnet" "wordpress_private_subnet" {
  count             = 3
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, count.index + 3)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "WordPressPrivateSubnet${count.index + 1}"
  }
}

resource "aws_route_table" "wordpress_public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressPublicRouteTable"
  }
}

resource "aws_route_table" "wordpress_private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressPrivateRouteTable"
  }
}

resource "aws_route" "wordpress_public_route" {
  route_table_id         = aws_route_table.wordpress_public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table_association" "wordpress_public_route_association" {
  count          = 3
  subnet_id      = aws_subnet.wordpress_public_subnet[count.index].id
  route_table_id = aws_route_table.wordpress_public_route_table.id
}

resource "aws_route_table_association" "wordpress_private_route_association" {
  count          = 3
  subnet_id      = aws_subnet.wordpress_private_subnet[count.index].id
  route_table_id = aws_route_table.wordpress_private_route_table.id
}

# Security groups
resource "aws_security_group" "wordpress_web_server_sg" {
  name        = "WordPressWebServerSG"
  description = "Security group for the WordPress web server"
  vpc_id      = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressWebServerSG"
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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "wordpress_rds_sg" {
  name        = "WordPressRDSSG"
  description = "Security group for the WordPress RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressRDSSG"
  }

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_web_server_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 instances
resource "aws_instance" "wordpress_instance" {
  count         = 3
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.wordpress_web_server_sg.id
  ]
  subnet_id = aws_subnet.wordpress_private_subnet[count.index].id
  tags = {
    Name = "WordPressInstance${count.index + 1}"
  }
}

# RDS instance
resource "aws_db_instance" "wordpress_rds_instance" {
  allocated_storage    = 20
  engine               = var.rds_engine
  engine_version       = "5.7"
  instance_class       = var.rds_instance_class
  name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = "wordpresspassword"
  parameter_group_name = "default.mysql5.7"
  vpc_security_group_ids = [
    aws_security_group.wordpress_rds_sg.id
  ]
  availability_zone = var.availability_zones[0]
  tags = {
    Name = "WordPressRDSInstance"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = aws_subnet.wordpress_public_subnet.*.id
  security_groups = [aws_security_group.wordpress_web_server_sg.id]
  tags = {
    Name = "WordPressELB"
  }

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
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
  name                      = "WordPressASG"
  max_size                  = 3
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity          = 1
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = aws_subnet.wordpress_private_subnet.*.id
  tags = [
    {
      key                 = "Name"
      value               = "WordPressASG"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.wordpress_web_server_sg.id
  ]
  key_name               = "wordpresskey"
  user_data              = file("wordpress.sh")
  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

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
  bucket = "wordpress-bucket"
  acl    = "private"
  tags = {
    Name = "WordPressS3Bucket"
  }
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_route53_zone" {
  name = var.route53_domain
  tags = {
    Name = "WordPressRoute53Zone"
  }
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name    = var.route53_domain
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cfd.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cfd.zone_id
    evaluate_target_health = false
  }
}

# Outputs
output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_rds_instance_endpoint" {
  value = aws_db_instance.wordpress_rds_instance.endpoint
}

output "wordpress_asg_id" {
  value = aws_autoscaling_group.wordpress_asg.id
}

output "wordpress_cfd_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cfd.domain_name
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3_bucket.id
}

output "wordpress_route53_zone_id" {
  value = aws_route53_zone.wordpress_route53_zone.id
}
