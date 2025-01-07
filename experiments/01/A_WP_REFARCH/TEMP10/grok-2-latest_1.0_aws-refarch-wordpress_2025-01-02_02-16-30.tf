terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Provider configuration
provider "aws" {
  region = var.aws_region
}

# VPC and networking resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "WordPressVPC"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "public_subnet" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "public-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "private_subnet" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "private-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "WordPressIGW"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name        = "PublicRouteTable"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "PrivateRouteTable"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table_association" "private_subnet_association" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security Groups
resource "aws_security_group" "web_server_sg" {
  name        = "web-server-sg"
  description = "Security group for web server"
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
    cidr_blocks = var.admin_ips
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WebServerSG"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Security group for RDS"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.web_server_sg.id]
  }

  tags = {
    Name        = "RDSSG"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group" "elb_sg" {
  name        = "elb-sg"
  description = "Security group for ELB"
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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "ELBSG"
    Environment = var.environment
    Project     = var.project
  }
}

# EC2 instances for WordPress
resource "aws_instance" "wordpress_instance" {
  ami           = var.wordpress_ami
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public_subnet[0].id
  vpc_security_group_ids = [
    aws_security_group.web_server_sg.id,
  ]
  key_name = aws_key_pair.wordpress_key.key_name

  user_data = file("${path.module}/wordpress-userdata.sh")

  tags = {
    Name        = "WordPressInstance"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_key_pair" "wordpress_key" {
  key_name   = "wordpress-key"
  public_key = file("${path.module}/wordpress_key.pub")
}

# RDS instance for the WordPress database
resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = var.db_allocated_storage
  engine               = var.db_engine
  engine_version       = var.db_engine_version
  instance_class       = var.db_instance_class
  name                 = "wordpressdb"
  username             = var.db_username
  password             = var.db_password
  parameter_group_name = var.db_parameter_group
  skip_final_snapshot  = true
  vpc_security_group_ids = [
    aws_security_group.rds_sg.id,
  ]
  multi_az = var.db_multi_az

  tags = {
    Name        = "WordPressDB"
    Environment = var.environment
    Project     = var.project
  }
}

# Elastic Load Balancer
resource "aws_lb" "wordpress_alb" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.elb_sg.id]
  subnets            = aws_subnet.public_subnet.*.id

  tags = {
    Name        = "WordPressALB"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_lb_target_group" "wordpress_tg" {
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    path                = "/"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 6
    interval            = 30
    matcher             = "200-399"
  }

  tags = {
    Name        = "WordPressTG"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

# Auto Scaling Group for EC2 instances
resource "aws_launch_configuration" "wordpress_lc" {
  name_prefix          = "wordpress-lc-"
  image_id             = var.wordpress_ami
  instance_type        = var.instance_type
  security_groups      = [aws_security_group.web_server_sg.id]
  key_name             = aws_key_pair.wordpress_key.key_name
  user_data            = file("${path.module}/wordpress-userdata.sh")

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  name                 = "wordpress-asg"
  min_size             = var.asg_min_size
  max_size             = var.asg_max_size
  desired_capacity     = var.asg_desired_capacity
  vpc_zone_identifier  = aws_subnet.public_subnet.*.id
  launch_configuration = aws_launch_configuration.wordpress_lc.name

  tag {
    key                 = "Name"
    value               = "WordPressASGInstance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project
    propagate_at_launch = true
  }
}

# CloudFront distribution for content delivery
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.wordpress_bucket.bucket_regional_domain_name
    origin_id   = "S3-wordpress-bucket"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-wordpress-bucket"

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
    cloudfront_default_certificate = true
  }

  tags = {
    Name        = "WordPressCloudFront"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "OAI for WordPress S3 bucket"
}

# S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-bucket-${var.environment}-${var.project}"

  tags = {
    Name        = "WordPressBucket"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_s3_bucket_public_access_block" "wordpress_bucket_block_public_access" {
  bucket = aws_s3_bucket.wordpress_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name

  tags = {
    Name        = "WordPressZone"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route53_record" "wordpress_alb" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.wordpress_alb.dns_name
    zone_id                = aws_lb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "wordpress_cloudfront" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "cdn.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "wordpress_cpu_high" {
  alarm_name          = "wordpress-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_sns_topic.wordpress_alerts.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.wordpress_asg.name
  }
}

resource "aws_sns_topic" "wordpress_alerts" {
  name = "wordpress-alerts"

  tags = {
    Name        = "WordPressAlerts"
    Environment = var.environment
    Project     = var.project
  }
}

# Variables
variable "aws_region" {
  description = "AWS region to deploy resources"
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "environment" {
  description = "Environment tag"
  default     = "dev"
}

variable "project" {
  description = "Project tag"
  default     = "wordpress"
}

variable "admin_ips" {
  description = "List of IP addresses allowed to access the bastion host"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "wordpress_ami" {
  description = "AMI ID for WordPress EC2 instances"
  default     = "ami-xxxxxxxx"
}

variable "instance_type" {
  description = "EC2 instance type for WordPress"
  default     = "t2.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS"
  default     = 20
}

variable "db_engine" {
  description = "Database engine type for RDS"
  default     = "mysql"
}

variable "db_engine_version" {
  description = "Database engine version for RDS"
  default     = "5.7.30"
}

variable "db_instance_class" {
  description = "Instance class for RDS"
  default     = "db.t2.micro"
}

variable "db_username" {
  description = "Username for RDS database"
  default     = "admin"
}

variable "db_password" {
  description = "Password for RDS database"
  default     = "password123"
}

variable "db_parameter_group" {
  description = "Parameter group for RDS"
  default     = "default.mysql5.7"
}

variable "db_multi_az" {
  description = "Whether to enable Multi-AZ deployment for RDS"
  default     = false
}

variable "asg_min_size" {
  description = "Minimum size of the Auto Scaling Group"
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum size of the Auto Scaling Group"
  default     = 3
}

variable "asg_desired_capacity" {
  description = "Desired capacity of the Auto Scaling Group"
  default     = 1
}

variable "domain_name" {
  description = "Domain name for Route 53"
  default     = "example.com"
}

# Outputs
output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "public_subnet_ids" {
  value = aws_subnet.public_subnet.*.id
}

output "private_subnet_ids" {
  value = aws_subnet.private_subnet.*.id
}

output "alb_dns_name" {
  value = aws_lb.wordpress_alb.dns_name
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.s3_distribution.domain_name
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.wordpress_bucket.arn
}

output "route53_zone_id" {
  value = aws_route53_zone.wordpress_zone.zone_id
}

output "sns_topic_arn" {
  value = aws_sns_topic.wordpress_alerts.arn
}
