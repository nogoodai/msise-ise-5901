terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Variables for user-configurable values
variable "aws_region" {
  description = "The AWS region to deploy into"
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "The CIDR blocks for the public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "The CIDR blocks for the private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
}

variable "availability_zones" {
  description = "The availability zones for the subnets"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "environment" {
  description = "The deployment environment (e.g., dev, prod)"
  default     = "dev"
}

variable "project_name" {
  description = "The name of the project"
  default     = "WordPress"
}

variable "instance_type" {
  description = "The EC2 instance type for WordPress"
  default     = "t2.micro"
}

variable "rds_instance_type" {
  description = "The RDS instance type for the WordPress database"
  default     = "db.t2.micro"
}

variable "domain_name" {
  description = "The domain name for the WordPress site"
  default     = "example.com"
}

# Provider Configuration
provider "aws" {
  region = var.aws_region
}

# Data Sources
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# VPC and Networking Resources
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  tags = {
    Name        = "${var.project_name}-VPC"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-IGW"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-PublicSubnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name        = "${var.project_name}-PrivateSubnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.project_name}-PublicRouteTable"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security Groups
resource "aws_security_group" "web_server" {
  name        = "${var.project_name}-WebServer-SG"
  description = "Allow web traffic to EC2 instances"
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
    cidr_blocks = ["0.0.0.0/0"] # Note: In production, restrict to specific IPs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-WebServer-SG"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-RDS-SG"
  description = "Allow RDS traffic from web servers"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-RDS-SG"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_security_group" "elb" {
  name        = "${var.project_name}-ELB-SG"
  description = "Allow inbound HTTP/HTTPS traffic to ELB"
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
    Name        = "${var.project_name}-ELB-SG"
    Environment = var.environment
    Project     = var.project_name
  }
}

# EC2 Instances for WordPress
resource "aws_launch_configuration" "web_server" {
  name_prefix          = "${var.project_name}-WebServer-"
  image_id             = data.aws_ami.amazon_linux.id
  instance_type        = var.instance_type
  security_groups      = [aws_security_group.web_server.id]
  key_name             = "your-ssh-key-name" # Replace with actual key name
  user_data            = file("install_wordpress.sh") # User data script to install WordPress

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "web_server" {
  name                 = "${var.project_name}-WebServer-ASG"
  launch_configuration = aws_launch_configuration.web_server.name
  vpc_zone_identifier  = aws_subnet.public.*.id
  min_size             = 1
  max_size             = 3
  desired_capacity     = 2
  health_check_type    = "ELB"

  tag {
    key                 = "Name"
    value               = "${var.project_name}-WebServer"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }
}

# RDS Instance for WordPress Database
resource "aws_db_subnet_group" "rds" {
  name       = "${var.project_name}-RDS-SubnetGroup"
  subnet_ids = aws_subnet.private.*.id

  tags = {
    Name        = "${var.project_name}-RDS-SubnetGroup"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_db_instance" "wordpress" {
  identifier             = "${var.project_name}-db"
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "5.7"
  instance_class         = var.rds_instance_type
  name                   = "wordpressdb"
  username               = "admin"
  password               = "your-secure-password" # Replace with actual password
  parameter_group_name   = "default.mysql5.7"
  multi_az               = true
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.rds.name
  skip_final_snapshot    = true

  tags = {
    Name        = "${var.project_name}-RDS"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Elastic Load Balancer
resource "aws_lb" "main" {
  name               = "${var.project_name}-ALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.elb.id]
  subnets            = aws_subnet.public.*.id

  tags = {
    Name        = "${var.project_name}-ALB"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lb_target_group" "web" {
  name     = "${var.project_name}-TG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 10
    matcher             = "200-299"
  }

  tags = {
    Name        = "${var.project_name}-TG"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.web_server.name
  lb_target_group_arn    = aws_lb_target_group.web.arn
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.static_assets.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.static_assets.id

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
    target_origin_id = aws_s3_bucket.static_assets.id

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
    cloudfront_default_certificate = true
  }

  tags = {
    Name        = "${var.project_name}-CloudFront"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "Origin Access Identity for ${var.project_name}"
}

# S3 Bucket for Static Assets
resource "aws_s3_bucket" "static_assets" {
  bucket = "${var.project_name}-static-assets-${var.environment}"

  tags = {
    Name        = "${var.project_name}-StaticAssets"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_s3_bucket_public_access_block" "static_assets_block" {
  bucket = aws_s3_bucket.static_assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = {
    Name        = "${var.project_name}-Route53Zone"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route53_record" "alb" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "cloudfront" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "cdn.${var.domain_name}"
  type    = "CNAME"
  ttl     = "300"
  records = [aws_cloudfront_distribution.s3_distribution.domain_name]
}

# Monitoring and Alarms
resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  alarm_name          = "${var.project_name}-CPUUtilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = []

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_server.name
  }

  tags = {
    Name        = "${var.project_name}-CPUUtilizationAlarm"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu_utilization" {
  alarm_name          = "${var.project_name}-RDSCPUUtilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors rds cpu utilization"
  alarm_actions       = []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.wordpress.identifier
  }

  tags = {
    Name        = "${var.project_name}-RDSCPUUtilizationAlarm"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "web_server_logs" {
  name              = "/aws/ec2/${var.project_name}-WebServer-Logs"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-WebServerLogs"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Outputs
output "vpc_id" {
  value = aws_vpc.main.id
}

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress.endpoint
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.s3_distribution.domain_name
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.static_assets.arn
}

output "route53_zone_id" {
  value = aws_route53_zone.main.zone_id
}
