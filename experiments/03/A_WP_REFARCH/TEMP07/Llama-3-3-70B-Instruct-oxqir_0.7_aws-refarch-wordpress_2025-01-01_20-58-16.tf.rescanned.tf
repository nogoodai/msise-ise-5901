# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0.0"
    }
  }
  required_version = ">= 1.3.0"
}

# Provider configuration for AWS
provider "aws" {
  region = var.region
}

# Define variables for the VPC
variable "region" {
  type        = string
  default     = "us-west-2"
  description = "The AWS region"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "The CIDR blocks for the public subnets"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
  description = "The CIDR blocks for the private subnets"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
  description = "The availability zones for the subnets"
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "The environment for the resources"
}

variable "project" {
  type        = string
  default     = "wordpress"
  description = "The project for the resources"
}

# Create the VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = var.environment
    Project     = var.project
  }
}

# Create the public subnets
resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PublicSubnet${count.index + 1}"
    Environment = var.environment
    Project     = var.project
  }
}

# Create the private subnets
resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PrivateSubnet${count.index + 1}"
    Environment = var.environment
    Project     = var.project
  }
}

# Create the internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = var.environment
    Project     = var.project
  }
}

# Create the public route table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = var.environment
    Project     = var.project
  }
}

# Create the private route table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = var.environment
    Project     = var.project
  }
}

# Create the route for the public route table
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Associate the public subnets with the public route table
resource "aws_route_table_association" "public_route_table_associations" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Associate the private subnets with the private route table
resource "aws_route_table_association" "private_route_table_associations" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Define variables for the security groups
variable "web_server_sg_description" {
  type        = string
  default     = "Security group for the web server"
  description = "The description for the web server security group"
}

variable "database_sg_description" {
  type        = string
  default     = "Security group for the database"
  description = "The description for the database security group"
}

variable "ssh_allowed_cidrs" {
  type        = list(string)
  default     = ["10.0.0.0/16"]
  description = "The allowed CIDRs for SSH access"
}

# Create the web server security group
resource "aws_security_group" "web_server_sg" {
  name        = "web-server-sg"
  description = var.web_server_sg_description
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow HTTP traffic from the VPC"
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow HTTPS traffic from the VPC"
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
    description = "Allow SSH traffic from the allowed CIDRs"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  tags = {
    Name        = "WebServerSG"
    Environment = var.environment
    Project     = var.project
  }
}

# Create the database security group
resource "aws_security_group" "database_sg" {
  name        = "database-sg"
  description = var.database_sg_description
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
    description     = "Allow MySQL traffic from the web server"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  tags = {
    Name        = "DatabaseSG"
    Environment = var.environment
    Project     = var.project
  }
}

# Define variables for the RDS instance
variable "rds_instance_class" {
  type        = string
  default     = "db.t2.micro"
  description = "The instance class for the RDS instance"
}

variable "rds_engine" {
  type        = string
  default     = "mysql"
  description = "The engine for the RDS instance"
}

# Create the RDS instance
resource "aws_db_instance" "wordpress_rds" {
  identifier           = "wordpress-rds"
  instance_class       = var.rds_instance_class
  engine               = var.rds_engine
  engine_version       = "8.0"
  username             = "wordpress"
  password             = random_password.rds_password.result
  vpc_security_group_ids = [aws_security_group.database_sg.id]
  availability_zone   = var.availability_zones[0]
  storage_encrypted    = true
  backup_retention_period = 12
  monitoring_interval = "30"
  iam_database_authentication_enabled = true
  skip_final_snapshot = true
  tags = {
    Name        = "WordPressRDS"
    Environment = var.environment
    Project     = var.project
  }
}

resource "random_password" "rds_password" {
  length = 16
  special = true
}

# Define variables for the ELB
variable "elb_name" {
  type        = string
  default     = "wordpress-elb"
  description = "The name for the ELB"
}

variable "elb_port" {
  type        = number
  default     = 80
  description = "The port for the ELB"
}

# Create the ELB
resource "aws_elb" "wordpress_elb" {
  name            = var.elb_name
  subnets         = [aws_subnet.public_subnets[0].id, aws_subnet.public_subnets[1].id]
  security_groups = [aws_security_group.web_server_sg.id]
  access_logs {
    bucket        = aws_s3_bucket.elb_logs_bucket.id
    bucket_prefix = "elb-logs"
    interval      = 60
  }
  tags = {
    Name        = "WordPressELB"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_s3_bucket" "elb_logs_bucket" {
  bucket = "wordpress-elb-logs"
  acl    = "private"
  tags = {
    Name        = "ELBLogsBucket"
    Environment = var.environment
    Project     = var.project
  }
}

# Create the ELB listener
resource "aws_elb_listener" "wordpress_elb_listener" {
  load_balancer_name = aws_elb.wordpress_elb.name
  port              = var.elb_port
  protocol          = "HTTP"
  instance_port     = var.elb_port
  instance_protocol = "HTTP"
}

# Define variables for the EC2 instance
variable "ec2_instance_type" {
  type        = string
  default     = "t2.micro"
  description = "The instance type for the EC2 instance"
}

variable "ec2_ami" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
  description = "The AMI for the EC2 instance"
}

# Create the EC2 instance
resource "aws_instance" "wordpress_ec2" {
  ami           = var.ec2_ami
  instance_type = var.ec2_instance_type
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  availability_zone   = var.availability_zones[0]
  ebs_optimized = true
  monitoring = true
  tags = {
    Name        = "WordPressEC2"
    Environment = var.environment
    Project     = var.project
  }
}

# Define variables for the Auto Scaling group
variable "asg_min_size" {
  type        = number
  default     = 1
  description = "The minimum size for the Auto Scaling group"
}

variable "asg_max_size" {
  type        = number
  default     = 3
  description = "The maximum size for the Auto Scaling group"
}

# Create the Auto Scaling group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "wordpress-asg"
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  vpc_zone_identifier = [aws_subnet.public_subnets[0].id, aws_subnet.public_subnets[1].id]
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  load_balancers = [aws_elb.wordpress_elb.name]
  tags = {
    Name        = "WordPressASG"
    Environment = var.environment
    Project     = var.project
  }
}

# Define variables for the launch configuration
variable "lc_instance_type" {
  type        = string
  default     = "t2.micro"
  description = "The instance type for the launch configuration"
}

variable "lc_ami" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
  description = "The AMI for the launch configuration"
}

# Create the launch configuration
resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = var.lc_ami
  instance_type = var.lc_instance_type
  security_groups = [aws_security_group.web_server_sg.id]
  ebs_optimized = true
}

# Define variables for the S3 bucket
variable "s3_bucket_name" {
  type        = string
  default     = "wordpress-bucket"
  description = "The name for the S3 bucket"
}

# Create the S3 bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = var.s3_bucket_name
  acl    = "private"
  versioning {
    enabled = true
  }
  logging {
    target_bucket = aws_s3_bucket.logging_bucket.id
    target_prefix = "logs/"
  }
  tags = {
    Name        = "WordPressBucket"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_s3_bucket" "logging_bucket" {
  bucket = "wordpress-logging-bucket"
  acl    = "private"
  tags = {
    Name        = "LoggingBucket"
    Environment = var.environment
    Project     = var.project
  }
}

# Define variables for the CloudFront distribution
variable "cloudfront_distribution_name" {
  type        = string
  default     = "wordpress-distribution"
  description = "The name for the CloudFront distribution"
}

# Create the CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_s3_bucket.wordpress_bucket.bucket_regional_domain_name
    origin_id   = "S3Origin"
  }
  enabled = true
  default_root_object = "index.html"
  aliases = ["example.com", "www.example.com"]
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
    viewer_protocol_policy = "https-only"
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
    acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "sni-only"
    minimum_protocol_version = "TLSv1.2_2019"
  }
  logging_config {
    bucket = aws_s3_bucket.logging_bucket.id
    prefix = "cloudfront-logs/"
  }
  tags = {
    Name        = "WordPressDistribution"
    Environment = var.environment
    Project     = var.project
  }
}

# Define variables for the Route 53 hosted zone
variable "route53_domain_name" {
  type        = string
  default     = "example.com"
  description = "The domain name for the Route 53 hosted zone"
}

# Create the Route 53 hosted zone
resource "aws_route53_zone" "wordpress_zone" {
  name = var.route53_domain_name
  tags = {
    Name        = "WordPressZone"
    Environment = var.environment
    Project     = var.project
  }
}

# Create the Route 53 query log
resource "aws_route53_query_log" "wordpress_query_log" {
  cloudwatch_log_group_arn = aws_cloudwatch_log_group.wordpress_query_log_group.arn
  s3_bucket_region        = aws_s3_bucket.logging_bucket.region
  s3_bucket_name          = aws_s3_bucket.logging_bucket.id
  hosted_zone_id           = aws_route53_zone.wordpress_zone.id
}

resource "aws_cloudwatch_log_group" "wordpress_query_log_group" {
  name = "wordpress-query-logs"
}

# Define variables for the Route 53 record
variable "route53_record_name" {
  type        = string
  default     = "example.com"
  description = "The name for the Route 53 record"
}

# Create the Route 53 record
resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.route53_record_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_distribution.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_distribution.zone_id
    evaluate_target_health = false
  }
}

# Create the AWS Shield Protection
resource "aws_shield_protection" "wordpress_protection" {
  name         = "WordPressProtection"
  resource_arn = aws_route53_zone.wordpress_zone.arn
}

# Output the ARN of the RDS instance
output "rds_instance_arn" {
  value       = aws_db_instance.wordpress_rds.arn
  description = "The ARN of the RDS instance"
}

# Output the DNS name of the ELB
output "elb_dns_name" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "The DNS name of the ELB"
}

# Output the ID of the S3 bucket
output "s3_bucket_id" {
  value       = aws_s3_bucket.wordpress_bucket.id
  description = "The ID of the S3 bucket"
}

# Output the domain name of the CloudFront distribution
output "cloudfront_distribution_domain_name" {
  value       = aws_cloudfront_distribution.wordpress_distribution.domain_name
  description = "The domain name of the CloudFront distribution"
}

# Output the ID of the Route 53 hosted zone
output "route53_hosted_zone_id" {
  value       = aws_route53_zone.wordpress_zone.id
  description = "The ID of the Route 53 hosted zone"
}
