terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Provider configuration
provider "aws" {
  region = var.aws_region
}

# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "WordPress-IGW"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name        = "WordPress-Public-Subnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name        = "WordPress-Private-Subnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name        = "WordPress-Public-Route-Table"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnets)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security Groups
resource "aws_security_group" "web_server_sg" {
  name        = "wordpress-web-server-sg"
  description = "Security group for WordPress web servers"
  vpc_id      = aws_vpc.main.id

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
    cidr_blocks = var.admin_ip_ranges
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WordPress-Web-Server-SG"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "wordpress-rds-sg"
  description = "Security group for WordPress RDS"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WordPress-RDS-SG"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group" "elb_sg" {
  name        = "wordpress-elb-sg"
  description = "Security group for WordPress ELB"
  vpc_id      = aws_vpc.main.id

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
    Name        = "WordPress-ELB-SG"
    Environment = var.environment
    Project     = var.project
  }
}

# EC2 Instances for WordPress
resource "aws_launch_configuration" "wordpress_lc" {
  name_prefix   = "wordpress-lc-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_server_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y httpd php php-mysqlnd
              sudo systemctl start httpd
              sudo systemctl enable httpd
              sudo wget -O /var/www/html/index.php https://raw.githubusercontent.com/WordPress/WordPress/master/wp-config-sample.php
              sudo sed -i 's/database_name_here/wordpress/g' /var/www/html/index.php
              sudo sed -i 's/username_here/wordpressuser/g' /var/www/html/index.php
              sudo sed -i 's/password_here/your_password/g' /var/www/html/index.php
              sudo chown -R apache:apache /var/www/html
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  name                 = "wordpress-asg"
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier  = aws_subnet.public[*].id
  min_size             = var.asg_min_size
  max_size             = var.asg_max_size
  health_check_type    = "ELB"

  tag {
    key                 = "Name"
    value               = "WordPress-Instance"
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

# RDS for WordPress Database
resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = var.db_allocated_storage
  engine               = var.db_engine
  engine_version       = var.db_engine_version
  instance_class       = var.db_instance_class
  name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = var.db_password
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db.id
  multi_az             = var.db_multi_az
  publicly_accessible  = false
  skip_final_snapshot  = true

  tags = {
    Name        = "WordPress-DB"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_db_subnet_group" "wordpress_db" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "WordPress-DB-Subnet-Group"
    Environment = var.environment
    Project     = var.project
  }
}

# Elastic Load Balancer
resource "aws_lb" "wordpress_elb" {
  name               = "wordpress-elb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.elb_sg.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name        = "WordPress-ELB"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress_elb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

resource "aws_lb_target_group" "wordpress_tg" {
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name        = "WordPress-TG"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.wordpress_asg.id
  lb_target_group_arn    = aws_lb_target_group.wordpress_tg.arn
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_lb.wordpress_elb.dns_name
    origin_id   = "WordPress-Origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "match-viewer"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.php"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WordPress-Origin"

    forwarded_values {
      query_string = true
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
    Name        = "WordPress-CloudFront"
    Environment = var.environment
    Project     = var.project
  }
}

# S3 Bucket for static assets
resource "aws_s3_bucket" "wordpress_static" {
  bucket = "${var.project}-wordpress-static-${var.environment}"
  acl    = "private"

  tags = {
    Name        = "WordPress-Static-Assets"
    Environment = var.environment
    Project     = var.project
  }
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name

  tags = {
    Name        = "WordPress-DNS-Zone"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route53_record" "wordpress_alb" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.wordpress_elb.dns_name
    zone_id                = aws_lb.wordpress_elb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "wordpress_cloudfront" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "cdn.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

# Monitoring and CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  alarm_name          = "wordpress-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.wordpress_asg.name
  }
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project}-wordpress-alerts-${var.environment}"

  tags = {
    Name        = "WordPress-Alerts"
    Environment = var.environment
    Project     = var.project
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

# Variables
variable "aws_region" {
  description = "AWS region to deploy resources"
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "List of public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  description = "List of private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "environment" {
  description = "Environment for tagging and naming"
  default     = "dev"
}

variable "project" {
  description = "Project name for tagging and naming"
  default     = "wordpress"
}

variable "admin_ip_ranges" {
  description = "IP ranges allowed to access instances via SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ami_id" {
  description = "AMI ID for EC2 instances"
  default     = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 AMI (HVM), SSD Volume Type
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t2.micro"
}

variable "asg_min_size" {
  description = "Minimum size of the Auto Scaling group"
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum size of the Auto Scaling group"
  default     = 3
}

variable "db_allocated_storage" {
  description = "Allocated storage for the RDS instance"
  default     = 20
}

variable "db_engine" {
  description = "RDS engine type"
  default     = "mysql"
}

variable "db_engine_version" {
  description = "RDS engine version"
  default     = "5.7"
}

variable "db_instance_class" {
  description = "RDS instance type"
  default     = "db.t2.micro"
}

variable "db_password" {
  description = "Password for the RDS instance"
  default     = "password123"
}

variable "db_multi_az" {
  description = "Enable multi-AZ deployment for RDS"
  default     = false
}

variable "domain_name" {
  description = "Domain name for WordPress"
  default     = "example.com"
}

# Outputs
output "elb_dns_name" {
  value       = aws_lb.wordpress_elb.dns_name
  description = "DNS name of the ELB"
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.wordpress_distribution.domain_name
  description = "Domain name of the CloudFront distribution"
}

output "s3_bucket_arn" {
  value       = aws_s3_bucket.wordpress_static.arn
  description = "ARN of the S3 bucket for static assets"
}

output "rds_endpoint" {
  value       = aws_db_instance.wordpress_db.endpoint
  description = "Endpoint of the RDS instance"
}

output "route53_zone_id" {
  value       = aws_route53_zone.wordpress_zone.zone_id
  description = "Zone ID of the Route 53 hosted zone"
}
