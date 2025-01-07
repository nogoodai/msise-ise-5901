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

# Variables and mappings for reusable values
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
}

variable "db_instance_class" {
  type        = string
  default     = "db.t2.small"
}

variable "rsa_public_key" {
  type        = string
  default     = "your-rsa-public-key"
}

variable "wordpress_domain" {
  type        = string
  default     = "example.com"
}

variable "wordpress_bucket_name" {
  type        = string
  default     = "wordpress-bucket"
}

# VPC and subnets
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "wordpress-vpc"
  }
}

resource "aws_subnet" "public_subnets" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, length(var.availability_zones) + count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "private-subnet-${count.index + 1}"
  }
}

# Internet gateway and route tables
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "wordpress-igw"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "private-route-table"
  }
}

# Associations between subnets and route tables
resource "aws_route_table_association" "publicassociation" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "privateassociation" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security groups for EC2 instances, RDS, and ELB
resource "aws_security_group" "wordpress_ec2_sg" {
  name        = "wordpress-ec2-sg"
  description = "Security group for WordPress EC2 instances"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
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
    Name = "wordpress-ec2-sg"
  }
}

resource "aws_security_group" "wordpress_rds_sg" {
  name        = "wordpress-rds-sg"
  description = "Security group for WordPress RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_ec2_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "wordpress-rds-sg"
  }
}

resource "aws_security_group" "wordpress_elb_sg" {
  name        = "wordpress-elb-sg"
  description = "Security group for WordPress ELB"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
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
    Name = "wordpress-elb-sg"
  }
}

# RDS instance for the WordPress database
resource "aws_db_instance" "wordpress_rds" {
  identifier             = "wordpress-rds"
  instance_class         = var.db_instance_class
  engine                  = "mysql"
  engine_version         = "8.0.28"
  allocated_storage      = 20
  storage_type           = "gp2"
  vpc_security_group_ids = [aws_security_group.wordpress_rds_sg.id]
  availability_zone     = var.availability_zones[0]
  multi_az              = true
  username               = "wordpressuser"
  password               = "wordpresspassword"
  parameter_group_name  = "default.mysql8.0"
  publicly_accessible   = false
  tags = {
    Name = "wordpress-rds"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_elb_sg.id]
  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
  tags = {
    Name = "wordpress-elb"
  }
}

# Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "wordpress-asg"
  max_size            = 3
  min_size            = 1
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier = aws_subnet.private_subnets.*.id
  tags = [
    {
      key                 = "Name"
      value               = "wordpress-asg"
      propagate_at_launch = true
    },
  ]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.wordpress_ec2_sg.id]
  user_data = file("${path.module}/wordpress.sh")
  key_name = "wordpress-key"
}

# CloudFront distribution for content delivery
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = "wordpress-alb"
  }
  enabled = true
  default_root_object = "index.html"
  aliases = [var.wordpress_domain]
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.wordpress_cert.arn
    ssl_support_method  = "sni-only"
  }
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-alb"
    compress         = true
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

# S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = var.wordpress_bucket_name
  tags = {
    Name        = var.wordpress_bucket_name
    Environment = "production"
  }
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_zone" {
  name = var.wordpress_domain
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.wordpress_domain
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "wordpress_cname_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.wordpress_domain
  type    = "CNAME"
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

output "wordpress_cfd_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cfd.domain_name
}

output "wordpress_rds_instance_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "wordpress_asg_id" {
  value = aws_autoscaling_group.wordpress_asg.id
}
