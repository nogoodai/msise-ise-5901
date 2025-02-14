# Configure the AWS Provider
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
  availability_zone = "us-west-2b"
  tags = {
    Name        = "WordPressPrivateSubnet"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Public Route Table
resource "aws_route_table" "wordpress_public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressPublicRT"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Private Route Table
resource "aws_route_table" "wordpress_private_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressPrivateRT"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Route Table Associations
resource "aws_route_table_association" "wordpress_public_rt_assoc" {
  subnet_id      = aws_subnet.wordpress_public_subnet.id
  route_table_id = aws_route_table.wordpress_public_rt.id
}

resource "aws_route_table_association" "wordpress_private_rt_assoc" {
  subnet_id      = aws_subnet.wordpress_private_subnet.id
  route_table_id = aws_route_table.wordpress_private_rt.id
}

# Public Route
resource "aws_route" "wordpress_public_route" {
  route_table_id         = aws_route_table.wordpress_public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Security Group for EC2 Instances
resource "aws_security_group" "wordpress_ec2_sg" {
  name        = "WordPressEC2SG"
  description = "Security Group for WordPress EC2 Instances"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access from anywhere"
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP access from anywhere"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outgoing traffic"
  }
  tags = {
    Name        = "WordPressEC2SG"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Security Group for RDS
resource "aws_security_group" "wordpress_rds_sg" {
  name        = "WordPressRDSSG"
  description = "Security Group for WordPress RDS"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_ec2_sg.id]
    description     = "RDS access from EC2 instances"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outgoing traffic"
  }
  tags = {
    Name        = "WordPressRDSSG"
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
  subnet_id = aws_subnet.wordpress_public_subnet.id
  key_name               = "wordpress-ec2-key"
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
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = "db.t2.micro"
  name                 = "wordpressdb"
  username             = var.rds_username
  password             = var.rds_password
  vpc_security_group_ids = [
    aws_security_group.wordpress_rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  storage_encrypted = true
  backup_retention_period = 12
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]
  tags = {
    Name        = "WordPressRDS"
    Environment = "production"
    Project     = "wordpress"
  }
}

# DB Subnet Group for RDS
resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = [aws_subnet.wordpress_private_subnet.id]
  tags = {
    Name        = "WordPressRDSSubnetGroup"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = [aws_subnet.wordpress_public_subnet.id]
  security_groups = [aws_security_group.wordpress_ec2_sg.id]
  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 80
    lb_protocol        = "http"
  }
  access_logs {
    bucket        = aws_s3_bucket.wordpress_elb_logs.id
    bucket_prefix = "elb-logs"
    interval      = 60
  }
  tags = {
    Name        = "WordPressELB"
    Environment = "production"
    Project     = "wordpress"
  }
}

# S3 Bucket for ELB Logs
resource "aws_s3_bucket" "wordpress_elb_logs" {
  bucket = "wordpress-elb-logs"
  acl    = "private"
  tags = {
    Name        = "WordPressELBLogs"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Auto Scaling Group for EC2 Instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "WordPressASG"
  max_size            = 5
  min_size            = 1
  desired_capacity    = 1
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier = aws_subnet.wordpress_public_subnet.id
  load_balancers = [aws_elb.wordpress_elb.name]
  tags = [
    {
      key                 = "Name"
      value               = "WordPressASG"
      propagate_at_launch = true
    }
  ]
}

# Launch Configuration for EC2 Instances
resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  security_groups = [
    aws_security_group.wordpress_ec2_sg.id
  ]
  key_name               = "wordpress-ec2-key"
  user_data = file("${path.module}/wordpress-user-data.sh")
  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }
  enabled = true
  default_root_object = "index.html"
  aliases = ["example.com"]
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
  logging_config {
    bucket = aws_s3_bucket.wordpress_cfd_logs.id
    prefix = "cfd-logs"
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "sni-only"
    minimum_protocol_version = "TLSv1.2"
  }
}

# S3 Bucket for CloudFront Logs
resource "aws_s3_bucket" "wordpress_cfd_logs" {
  bucket = "wordpress-cfd-logs"
  acl    = "private"
  tags = {
    Name        = "WordPressCFDLogs"
    Environment = "production"
    Project     = "wordpress"
  }
}

# S3 Bucket for Static Assets
resource "aws_s3_bucket" "wordpress_s3" {
  bucket = "example-bucket"
  acl    = "private"
  versioning {
    enabled = true
  }
  logging {
    target_bucket = aws_s3_bucket.wordpress_s3_logs.id
    target_prefix = "s3-logs/"
  }
  tags = {
    Name        = "WordPressS3"
    Environment = "production"
    Project     = "wordpress"
  }
}

# S3 Bucket for S3 Logs
resource "aws_s3_bucket" "wordpress_s3_logs" {
  bucket = "wordpress-s3-logs"
  acl    = "private"
  tags = {
    Name        = "WordPressS3Logs"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Route 53 DNS Configuration
resource "aws_route53_record" "wordpress_route53" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name    = "example.com"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cfd.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cfd.zone_id
    evaluate_target_health = false
  }
}

# Route 53 Zone
resource "aws_route53_zone" "wordpress_route53_zone" {
  name = "example.com"
  tags = {
    Name        = "WordPressRoute53Zone"
    Environment = "production"
    Project     = "wordpress"
  }
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "wordpress_cwd" {
  dashboard_name = "WordPressCWD"
  dashboard_body = file("${path.module}/wordpress-dashboard.json")
}

# VPC Flow Log
resource "aws_flow_log" "wordpress_vpc_flow_log" {
  iam_role_arn    = aws_iam_role.wordpress_vpc_flow_log.arn
  log_destination = aws_s3_bucket.wordpress_vpc_flow_log.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.wordpress_vpc.id
}

# IAM Role for VPC Flow Log
resource "aws_iam_role" "wordpress_vpc_flow_log" {
  name        = "WordPressVPCFlowLog"
  description = "IAM Role for VPC Flow Log"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
}

# S3 Bucket for VPC Flow Log
resource "aws_s3_bucket" "wordpress_vpc_flow_log" {
  bucket = "wordpress-vpc-flow-log"
  acl    = "private"
  tags = {
    Name        = "WordPressVPCFlowLog"
    Environment = "production"
    Project     = "wordpress"
  }
}

variable "rds_username" {
  type        = string
  description = "RDS username"
  sensitive   = true
}

variable "rds_password" {
  type        = string
  description = "RDS password"
  sensitive   = true
}

output "wordpress_elb_dns_name" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "The DNS name of the ELB"
}

output "wordpress_rds_endpoint" {
  value       = aws_db_instance.wordpress_rds.endpoint
  description = "The endpoint of the RDS instance"
}

output "wordpress_s3_bucket_name" {
  value       = aws_s3_bucket.wordpress_s3.bucket
  description = "The name of the S3 bucket"
}

output "wordpress_cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.wordpress_cfd.id
  description = "The ID of the CloudFront distribution"
}

output "wordpress_route53_zone_id" {
  value       = aws_route53_zone.wordpress_route53_zone.id
  description = "The ID of the Route 53 zone"
}
