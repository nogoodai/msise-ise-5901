provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

variable "vpc_cidr" {
  type        = string
  description = "The CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  type        = list(string)
  description = "A list of public subnet CIDR blocks."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  type        = list(string)
  description = "A list of private subnet CIDR blocks."
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  type        = list(string)
  description = "A list of availability zones."
  default     = ["us-west-2a", "us-west-2b"]
}

variable "instance_type" {
  type        = string
  description = "The instance type for the EC2 instance."
  default     = "t2.micro"
}

variable "ami_id" {
  type        = string
  description = "The ID of the AMI to use for the EC2 instance."
  default     = "ami-0c94855ba95c71c99"
}

variable "key_name" {
  type        = string
  description = "The name of the key pair to use for the EC2 instance."
  default     = "wordpress-key"
}

variable "db_instance_class" {
  type        = string
  description = "The instance class for the RDS instance."
  default     = "db.t2.small"
}

variable "db_username" {
  type        = string
  description = "The username for the RDS instance."
  default     = "wordpress"
}

variable "db_password" {
  type        = string
  description = "The password for the RDS instance."
  default     = "wordpress123"
}

variable "db_name" {
  type        = string
  description = "The name of the database for the RDS instance."
  default     = "wordpressdb"
}

variable "wordpress_version" {
  type        = string
  description = "The version of WordPress to use."
  default     = "latest"
}

variable "efs_performance_mode" {
  type        = string
  description = "The performance mode for the EFS file system."
  default     = "generalPurpose"
}

variable "efs_transition_to_ia" {
  type        = string
  description = "The transition to IA storage class for the EFS file system."
  default     = "AFTER_30_DAYS"
}

variable "cloudfront_origin_path" {
  type        = string
  description = "The origin path for the CloudFront distribution."
  default     = "/wordpress"
}

variable "cloudfront_ssl_certificate" {
  type        = string
  description = "The SSL certificate ARN for the CloudFront distribution."
  default     = "arn:aws:iam::123456789012:server-certificate/wordpress-ssl-certificate"
}

variable "route53_zone_name" {
  type        = string
  description = "The name of the Route 53 zone."
  default     = "example.com"
}

# VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# Public Subnets
resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnets)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = false
  tags = {
    Name        = "WordPressPublicSubnet-${count.index}"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# Private Subnets
resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnets)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "WordPressPrivateSubnet-${count.index}"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# Public Route Table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name        = "WordPressPublicRouteTable"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# Private Route Table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressPrivateRouteTable"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public_route_table_associations" {
  count = length(var.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_route_table_associations" {
  count = length(var.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
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
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WordPressSG"
    Environment = "prod"
    Project     = "wordpress"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "RDSSG"
  description = "Security group for RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
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
    Environment = "prod"
    Project     = "wordpress"
  }
}

# EC2 Instances
resource "aws_instance" "wordpress_instance" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  subnet_id = aws_subnet.private_subnets[0].id
  key_name = var.key_name
  associate_public_ip_address = false
  monitoring = true
  tags = {
    Name        = "WordPressInstance"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# RDS Instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = var.db_instance_class
  name                 = var.db_name
  username             = var.db_username
  password             = var.db_password
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = "default-vpc-12345678"
  multi_az             = true
  storage_encrypted    = true
  backup_retention_period = 12
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]
  iam_database_authentication_enabled = true
  tags = {
    Name        = "WordPressRDS"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_sg.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol        = "http"
  }

  access_logs {
    bucket        = "wordpress-elb-logs"
    bucket_prefix = "wordpress-elb-logs"
    interval      = 60
  }

  tags = {
    Name        = "WordPressELB"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  min_size                  = 1
  max_size                  = 5
  vpc_zone_identifier       = aws_subnet.private_subnets.*.id
  target_group_arns         = [aws_lb_target_group.wordpress_tg.arn]
  health_check_type         = "EC2"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "WordPressASG"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "prod"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = "wordpress"
    propagate_at_launch = true
  }
}

# Launch Configuration
resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  security_groups = [aws_security_group.wordpress_sg.id]
  user_data = file("./wordpress.sh")
  ebs_optimized = true
}

# Target Group
resource "aws_lb_target_group" "wordpress_tg" {
  name     = "WordPressTG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "WordPressTG"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressOrigin"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases = ["example.com"]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WordPressOrigin"

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
    acm_certificate_arn = var.cloudfront_ssl_certificate
    ssl_support_method  = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  logging_config {
    bucket = "wordpress-cf-logs.s3.amazonaws.com"
    prefix = "wordpress-cf-logs"
  }

  web_acl_id = "arn:aws:wafv2:us-west-2:123456789012:global/webacl/WordPressWAF"

  tags = {
    Name        = "WordPressCF"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# S3 Bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "example.com"
  acl    = "private"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  logging {
    target_bucket = "wordpress-s3-logs"
    target_prefix = "wordpress-s3-logs/"
  }

  tags = {
    Name        = "WordPressS3Bucket"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# Route 53 Record
resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id                = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }

  tags = {
    Name        = "WordPressRoute53Record"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "wordpress_alarm" {
  alarm_name          = "WordPressAlarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_actions       = [aws_autoscaling_policy.wordpress_policy.arn]
  tags = {
    Name        = "WordPressAlarm"
    Environment = "prod"
    Project     = "wordpress"
  }
}

resource "aws_autoscaling_policy" "wordpress_policy" {
  name                   = "WordPressPolicy"
  policy_type           = "SimpleScaling"
  resource_id           = aws_autoscaling_group.wordpress_asg.id
  scaling_adjustment    = 1
  adjustment_type       = "ChangeInCapacity"
  cooldown               = 300
  tags = {
    Name        = "WordPressPolicy"
    Environment = "prod"
    Project     = "wordpress"
  }
}

resource "aws_cloudwatch_log_group" "wordpress_log_group" {
  name = "WordPressLogGroup"
  retention_in_days = 7
  tags = {
    Name        = "WordPressLogGroup"
    Environment = "prod"
    Project     = "wordpress"
  }
}

resource "aws_cloudwatch_log_stream" "wordpress_log_stream" {
  name           = "WordPressLogStream"
  log_group_name = aws_cloudwatch_log_group.wordpress_log_group.name
  tags = {
    Name        = "WordPressLogStream"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# EFS
resource "aws_efs_file_system" "wordpress_efs" {
  creation_token = "wordpress-efs"
  encrypted      = true
  tags = {
    Name        = "WordPressEFS"
    Environment = "prod"
    Project     = "wordpress"
  }
}

resource "aws_efs_mount_target" "wordpress_efs_mount" {
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = aws_subnet.private_subnets[0].id
}

# Elasticache
resource "aws_elasticache_cluster" "wordpress_elasticache" {
  cluster_id           = "wordpress-elasticache"
  engine               = "redis"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis6.x"
  port                 = 6379
  tags = {
    Name        = "WordPressElasticache"
    Environment = "prod"
    Project     = "wordpress"
  }
}

output "wordpress_elb_dns_name" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "The DNS name of the Elastic Load Balancer."
}

output "wordpress_rds_endpoint" {
  value       = aws_db_instance.wordpress_rds.endpoint
  description = "The endpoint of the RDS instance."
}

output "wordpress_s3_bucket_name" {
  value       = aws_s3_bucket.wordpress_bucket.bucket
  description = "The name of the S3 bucket."
}

output "wordpress_cf_distribution_id" {
  value       = aws_cloudfront_distribution.wordpress_cf.id
  description = "The ID of the CloudFront distribution."
}

output "wordpress_route53_record_name" {
  value       = aws_route53_record.wordpress_record.name
  description = "The name of the Route 53 record."
}
