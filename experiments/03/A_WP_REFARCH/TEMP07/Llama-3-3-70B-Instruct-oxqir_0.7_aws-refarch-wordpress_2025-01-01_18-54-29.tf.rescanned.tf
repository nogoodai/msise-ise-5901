# Configure the AWS Provider
provider "aws" {
  region = var.region
}

# VPC Configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  enable_classiclink   = false
  instance_tenancy     = "default"

  tags = {
    Name        = "WordPressVPC"
    Environment = var.environment
  }
}

# Subnets
resource "aws_subnet" "public_subnet_1" {
  cidr_block = var.public_cidr_block_1
  vpc_id     = aws_vpc.wordpress_vpc.id
  availability_zone = var.availability_zone_1

  tags = {
    Name        = "PublicSubnet1"
    Environment = var.environment
  }
}

resource "aws_subnet" "public_subnet_2" {
  cidr_block = var.public_cidr_block_2
  vpc_id     = aws_vpc.wordpress_vpc.id
  availability_zone = var.availability_zone_2

  tags = {
    Name        = "PublicSubnet2"
    Environment = var.environment
  }
}

resource "aws_subnet" "private_subnet_1" {
  cidr_block = var.private_cidr_block_1
  vpc_id     = aws_vpc.wordpress_vpc.id
  availability_zone = var.availability_zone_1

  tags = {
    Name        = "PrivateSubnet1"
    Environment = var.environment
  }
}

resource "aws_subnet" "private_subnet_2" {
  cidr_block = var.private_cidr_block_2
  vpc_id     = aws_vpc.wordpress_vpc.id
  availability_zone = var.availability_zone_2

  tags = {
    Name        = "PrivateSubnet2"
    Environment = var.environment
  }
}

# Internet Gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "WordPressIGW"
    Environment = var.environment
  }
}

# Route Tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "PublicRouteTable"
    Environment = var.environment
  }
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "PrivateRouteTable"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public_subnet_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnet_1" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_subnet_2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_route_table.id
}

# Security Groups
resource "aws_security_group" "wordpress_sg" {
  name        = "WordPressSG"
  description = "Security group for WordPress instances"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WordPressSG"
    Environment = var.environment
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
    Environment = var.environment
  }
}

resource "aws_security_group" "elb_sg" {
  name        = "ELBSG"
  description = "Security group for ELB"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "ELBSG"
    Environment = var.environment
  }
}

# EC2 instances for WordPress
resource "aws_instance" "wordpress_instance_1" {
  ami           = var.ami
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  subnet_id = aws_subnet.private_subnet_1.id
  key_name = var.key_name
  associate_public_ip_address = false
  monitoring = true

  tags = {
    Name        = "WordPressInstance1"
    Environment = var.environment
  }
}

resource "aws_instance" "wordpress_instance_2" {
  ami           = var.ami
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  subnet_id = aws_subnet.private_subnet_2.id
  key_name = var.key_name
  associate_public_ip_address = false
  monitoring = true

  tags = {
    Name        = "WordPressInstance2"
    Environment = var.environment
  }
}

# RDS instance for WordPress database
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = var.rds_allocated_storage
  engine               = var.rds_engine
  engine_version       = var.rds_engine_version
  instance_class       = var.rds_instance_class
  name                 = var.rds_name
  username             = var.rds_username
  password             = var.rds_password
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  parameter_group_name = var.rds_parameter_group_name
  storage_encrypted = true
  backup_retention_period = 12
  iam_database_authentication_enabled = true

  tags = {
    Name        = "WordPressRDS"
    Environment = var.environment
  }
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]

  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = var.environment
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  security_groups = [aws_security_group.elb_sg.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  access_logs {
    bucket        = aws_s3_bucket.wordpress_bucket.id
    bucket_prefix = "elb-logs"
    interval      = 60
  }

  tags = {
    Name        = "WordPressELB"
    Environment = var.environment
  }
}

# Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  max_size                  = var.asg_max_size
  min_size                  = var.asg_min_size
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity          = var.asg_desired_capacity
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_launch_config.name
  load_balancers = [aws_elb.wordpress_elb.name]

  tag {
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress_launch_config" {
  name          = "WordPressLaunchConfig"
  image_id      = var.ami
  instance_type = var.instance_type
  security_groups = [aws_security_group.wordpress_sg.id]
  key_name               = var.key_name
  ebs_optimized = true

  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront distribution for content delivery
resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
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
    acm_certificate_arn = aws_acm_certificate.wordpress_cert.arn
  }

  logging_config {
    bucket = aws_s3_bucket.wordpress_bucket.id
    prefix = "cloudfront-logs"
  }
}

resource "aws_acm_certificate" "wordpress_cert" {
  domain_name       = var.domain_name
  validation_method = "EMAIL"
}

# S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = var.bucket_name
  acl    = "private"

  versioning {
    enabled = true
  }

  logging {
    target_bucket = aws_s3_bucket.wordpress_bucket.id
    target_prefix = "logs/"
  }

  tags = {
    Name        = "WordPressBucket"
    Environment = var.environment
  }
}

# Route 53 DNS configuration
resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
}

# VPC Flow Logs
resource "aws_flow_log" "wordpress_flow_log" {
  iam_role_arn    = aws_iam_role.flow_log_role.arn
  log_destination = aws_s3_bucket.wordpress_bucket.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.wordpress_vpc.id
}

resource "aws_iam_role" "flow_log_role" {
  name        = "FlowLogRole"
  description = "Role for VPC Flow Logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "flow_log_policy" {
  name        = "FlowLogPolicy"
  role        = aws_iam_role.flow_log_role.id
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Output critical information
output "elb_dns_name" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "The DNS name of the ELB"
}

output "rds_endpoint" {
  value       = aws_db_instance.wordpress_rds.endpoint
  description = "The endpoint of the RDS instance"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.wordpress_bucket.bucket
  description = "The name of the S3 bucket"
}

output "route53_record_name" {
  value       = aws_route53_record.wordpress_record.name
  description = "The name of the Route 53 record"
}

variable "region" {
  type        = string
  default     = "us-west-2"
  description = "The AWS region to deploy to"
}

variable "cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block of the VPC"
}

variable "public_cidr_block_1" {
  type        = string
  default     = "10.0.1.0/24"
  description = "The CIDR block of the first public subnet"
}

variable "public_cidr_block_2" {
  type        = string
  default     = "10.0.2.0/24"
  description = "The CIDR block of the second public subnet"
}

variable "private_cidr_block_1" {
  type        = string
  default     = "10.0.3.0/24"
  description = "The CIDR block of the first private subnet"
}

variable "private_cidr_block_2" {
  type        = string
  default     = "10.0.4.0/24"
  description = "The CIDR block of the second private subnet"
}

variable "availability_zone_1" {
  type        = string
  default     = "us-west-2a"
  description = "The first availability zone"
}

variable "availability_zone_2" {
  type        = string
  default     = "us-west-2b"
  description = "The second availability zone"
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "The list of allowed CIDR blocks for the security groups"
}

variable "ami" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
  description = "The ID of the AMI to use for the EC2 instances"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "The type of instance to use for the EC2 instances"
}

variable "key_name" {
  type        = string
  default     = "wordpress-key"
  description = "The name of the key pair to use for the EC2 instances"
}

variable "rds_allocated_storage" {
  type        = number
  default     = 20
  description = "The amount of storage to allocate to the RDS instance"
}

variable "rds_engine" {
  type        = string
  default     = "mysql"
  description = "The engine to use for the RDS instance"
}

variable "rds_engine_version" {
  type        = string
  default     = "8.0.23"
  description = "The version of the engine to use for the RDS instance"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.micro"
  description = "The class of instance to use for the RDS instance"
}

variable "rds_name" {
  type        = string
  default     = "wordpressdb"
  description = "The name of the RDS instance"
}

variable "rds_username" {
  type        = string
  default     = "admin"
  description = "The username to use for the RDS instance"
}

variable "rds_password" {
  type        = string
  sensitive   = true
  description = "The password to use for the RDS instance"
}

variable "rds_parameter_group_name" {
  type        = string
  default     = "default.mysql8.0"
  description = "The name of the parameter group to use for the RDS instance"
}

variable "asg_max_size" {
  type        = number
  default     = 2
  description = "The maximum size of the Auto Scaling group"
}

variable "asg_min_size" {
  type        = number
  default     = 1
  description = "The minimum size of the Auto Scaling group"
}

variable "asg_desired_capacity" {
  type        = number
  default     = 1
  description = "The desired capacity of the Auto Scaling group"
}

variable "bucket_name" {
  type        = string
  default     = "wordpress-bucket"
  description = "The name of the S3 bucket"
}

variable "domain_name" {
  type        = string
  default     = "example.com"
  description = "The domain name to use for the Route 53 record"
}

variable "environment" {
  type        = string
  default     = "Production"
  description = "The environment to deploy to"
}
