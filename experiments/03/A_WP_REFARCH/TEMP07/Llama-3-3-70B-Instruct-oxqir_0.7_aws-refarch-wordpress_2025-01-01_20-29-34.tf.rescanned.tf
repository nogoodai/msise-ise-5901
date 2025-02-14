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
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Subnets
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name        = "PublicSubnet"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name        = "PrivateSubnet"
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

# Route Tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
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

# Route Table Associations
resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnet_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

# Routes
resource "aws_route" "public_internet_gateway_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Security Groups
resource "aws_security_group" "wordpress_ec2_sg" {
  name        = "WordPressEC2SG"
  description = "Security group for WordPress EC2 instances"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow HTTP from VPC"
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow HTTPS from VPC"
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow SSH from VPC"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outgoing traffic"
  }
  tags = {
    Name        = "WordPressEC2SG"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_security_group" "wordpress_rds_sg" {
  name        = "WordPressRDSSG"
  description = "Security group for WordPress RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_ec2_sg.id]
    description     = "Allow MySQL from EC2 instances"
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

resource "aws_security_group" "wordpress_elb_sg" {
  name        = "WordPressELBSG"
  description = "Security group for WordPress ELB"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP from internet"
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS from internet"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outgoing traffic"
  }
  tags = {
    Name        = "WordPressELBSG"
    Environment = "production"
    Project     = "wordpress"
  }
}

# EC2 Instance for WordPress
resource "aws_instance" "wordpress_ec2" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  vpc_security_group_ids = [
    aws_security_group.wordpress_ec2_sg.id
  ]
  subnet_id = aws_subnet.private_subnet.id
  associate_public_ip_address = false
  monitoring = true
  ebs_optimized = true
  tags = {
    Name        = "WordPressEC2"
    Environment = "production"
    Project     = "wordpress"
  }
}

# RDS Instance for WordPress Database
resource "aws_db_instance" "wordpress_rds" {
  identifier        = "wordpress-rds"
  engine            = "mysql"
  engine_version   = "8.0.28"
  instance_class    = "db.t2.micro"
  allocated_storage = 20
  storage_type      = "gp2"
  username          = "admin"
  password          = "password"
  vpc_security_group_ids = [
    aws_security_group.wordpress_rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  backup_retention_period = 12
  storage_encrypted = true
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]
  tags = {
    Name        = "WordPressRDS"
    Environment = "production"
    Project     = "wordpress"
  }
}

# DB Subnet Group
resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = [aws_subnet.private_subnet.id]
  tags = {
    Name        = "WordPressRDSSubnetGroup"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = [aws_subnet.public_subnet.id]
  security_groups = [aws_security_group.wordpress_elb_sg.id]
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
  access_logs {
    bucket        = aws_s3_bucket.wordpress_s3_bucket.id
    bucket_prefix = "elb-logs"
    interval      = 60
  }
  tags = {
    Name        = "WordPressELB"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Auto Scaling Group for EC2 Instances
resource "aws_autoscaling_group" "wordpress_ec2_asg" {
  name                      = "wordpress-ec2-asg"
  launch_configuration      = aws_launch_configuration.wordpress_ec2_lc.name
  min_size                  = 1
  max_size                  = 3
  vpc_zone_identifier       = aws_subnet.private_subnet.id
  load_balancers            = [aws_elb.wordpress_elb.name]
  tags = [
    {
      key                 = "Name"
      value               = "WordPressEC2ASG"
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
    }
  ]
}

# Launch Configuration for EC2 Instances
resource "aws_launch_configuration" "wordpress_ec2_lc" {
  name          = "wordpress-ec2-lc"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  security_groups = [
    aws_security_group.wordpress_ec2_sg.id
  ]
  user_data = <<-EOF
              #!/bin/bash
              echo "Hello World!" > index.html
              EOF
  lifecycle {
    create_before_destroy = true
  }
  ebs_optimized = true
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb-origin"
  }
  enabled         = true
  is_ipv6_enabled = true
  aliases         = ["example.com"]
  default_root_object = "index.html"
  viewer_certificate {
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "sni-only"
    minimum_protocol_version = "TLSv1.2_2019"
  }
  logging_config {
    bucket = aws_s3_bucket.wordpress_s3_bucket.id
    prefix = "cf-logs"
  }
  tags = {
    Name        = "WordPressCF"
    Environment = "production"
    Project     = "wordpress"
  }
}

# S3 Bucket for Static Assets
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = "example-bucket"
  acl    = "private"
  versioning {
    enabled = true
  }
  logging {
    target_bucket = aws_s3_bucket.wordpress_s3_bucket.id
    target_prefix  = "/logs/"
  }
  tags = {
    Name        = "WordPressS3Bucket"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Route 53 DNS Configuration
resource "aws_route53_record" "wordpress_r53_record" {
  zone_id = aws_route53_zone.wordpress_r53_zone.id
  name    = "example.com"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cf.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cf.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "wordpress_r53_zone" {
  name = "example.com"
  tags = {
    Name        = "WordPressR53Zone"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Outputs
output "wordpress_elb_dns_name" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "The DNS name of the WordPress ELB"
}

output "wordpress_r53_record_name" {
  value       = aws_route53_record.wordpress_r53_record.name
  description = "The name of the WordPress Route 53 record"
}

output "wordpress_r53_zone_id" {
  value       = aws_route53_zone.wordpress_r53_zone.id
  description = "The ID of the WordPress Route 53 zone"
}

output "wordpress_s3_bucket_name" {
  value       = aws_s3_bucket.wordpress_s3_bucket.bucket
  description = "The name of the WordPress S3 bucket"
}

output "wordpress_cf_distribution_id" {
  value       = aws_cloudfront_distribution.wordpress_cf.id
  description = "The ID of the WordPress CloudFront distribution"
}

output "wordpress_cf_distribution_arn" {
  value       = aws_cloudfront_distribution.wordpress_cf.arn
  description = "The ARN of the WordPress CloudFront distribution"
}

output "wordpress_rds_instance_arn" {
  value       = aws_db_instance.wordpress_rds.arn
  description = "The ARN of the WordPress RDS instance"
}

output "wordpress_rds_instance_endpoint" {
  value       = aws_db_instance.wordpress_rds.endpoint
  description = "The endpoint of the WordPress RDS instance"
}

output "wordpress_rds_instance_id" {
  value       = aws_db_instance.wordpress_rds.id
  description = "The ID of the WordPress RDS instance"
}

output "wordpress_ec2_instance_id" {
  value       = aws_instance.wordpress_ec2.id
  description = "The ID of the WordPress EC2 instance"
}

output "wordpress_ec2_instance_public_ip" {
  value       = aws_instance.wordpress_ec2.private_ip
  description = "The private IP of the WordPress EC2 instance"
}
