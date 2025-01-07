terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Provider configuration for AWS
provider "aws" {
  region = var.aws_region
}

# VPC and Networking resources
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
    Name        = "WordPressIGW"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name        = "public-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name        = "private-subnet-${count.index + 1}"
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
    Name        = "public-route-table"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "private-route-table"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security Groups
resource "aws_security_group" "web_server" {
  name        = "web-server-sg"
  description = "Allow inbound HTTP, HTTPS, and SSH traffic"
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
    Name        = "web-server-sg"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group" "rds" {
  name        = "rds-sg"
  description = "Allow inbound MySQL/Aurora traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server.id]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.web_server.id]
  }

  tags = {
    Name        = "rds-sg"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group" "elb" {
  name        = "elb-sg"
  description = "Allow inbound HTTP and HTTPS traffic"
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
    Name        = "elb-sg"
    Environment = var.environment
    Project     = var.project
  }
}

# EC2 Instances for WordPress
resource "aws_launch_configuration" "web_server" {
  name_prefix          = "wordpress-"
  image_id             = var.ami_id
  instance_type        = var.instance_type
  security_groups     = [aws_security_group.web_server.id]
  key_name             = var.key_name
  user_data            = file("${path.module}/user_data.sh")
  iam_instance_profile = aws_iam_instance_profile.wordpress.name

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "web_server" {
  name                 = "wordpress-asg"
  max_size             = var.asg_max_size
  min_size             = var.asg_min_size
  health_check_type    = "ELB"
  load_balancers       = [aws_elb.wordpress.name]
  vpc_zone_identifier  = aws_subnet.public[*].id
  launch_configuration = aws_launch_configuration.web_server.name

  tag {
    key                 = "Name"
    value               = "WordPress-WebServer"
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

# RDS Instance for WordPress Database
resource "aws_db_instance" "wordpress" {
  identifier             = "wordpress-db"
  engine                 = var.db_engine
  engine_version         = var.db_engine_version
  instance_class         = var.db_instance_class
  allocated_storage      = var.db_allocated_storage
  storage_type           = var.db_storage_type
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  multi_az               = var.db_multi_az
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.wordpress.name
  parameter_group_name   = aws_db_parameter_group.wordpress.name
  skip_final_snapshot    = true

  tags = {
    Name        = "wordpress-db"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_db_subnet_group" "wordpress" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "wordpress-db-subnet-group"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_db_parameter_group" "wordpress" {
  name   = "wordpress-db-parameter-group"
  family = var.db_parameter_group_family

  parameter {
    name  = "character_set_server"
    value = "utf8"
  }

  parameter {
    name  = "character_set_client"
    value = "utf8"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress" {
  name               = "wordpress-elb"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.elb.id]
  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 30
  }

  tags = {
    Name        = "wordpress-elb"
    Environment = var.environment
    Project     = var.project
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_elb.wordpress.dns_name
    origin_id   = "WordPressOrigin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.php"

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

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name        = "wordpress-cloudfront"
    Environment = var.environment
    Project     = var.project
  }
}

# S3 Bucket for static assets
resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-${var.environment}-assets"
  acl    = "private"

  tags = {
    Name        = "wordpress-assets"
    Environment = var.environment
    Project     = var.project
  }
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress" {
  name = var.domain_name

  tags = {
    Name        = "wordpress-dns"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route53_record" "wordpress_alb" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_elb.wordpress.dns_name
    zone_id                = aws_elb.wordpress.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "wordpress_cloudfront" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = "cdn.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress.hosted_zone_id
    evaluate_target_health = false
  }
}

# Monitoring and Dashboards
resource "aws_cloudwatch_dashboard" "wordpress_dashboard" {
  dashboard_name = "WordPressDashboard"

  dashboard_body = <<EOF
{
  "widgets": [
    {
      "type": "metric",
      "x": 0,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [
            "AWS/EC2",
            "CPUUtilization",
            "InstanceId",
            "${aws_autoscaling_group.web_server.instances[0].id}"
          ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${var.aws_region}",
        "title": "EC2 CPU Utilization",
        "period": 300
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [
            "AWS/RDS",
            "CPUUtilization",
            "DBInstanceIdentifier",
            "${aws_db_instance.wordpress.identifier}"
          ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${var.aws_region}",
        "title": "RDS CPU Utilization",
        "period": 300
      }
    }
  ]
}
EOF
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "ec2_cpu_alarm" {
  alarm_name          = "wordpress-ec2-cpu-alarm"
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
    InstanceId = aws_autoscaling_group.web_server.instances[0].id
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu_alarm" {
  alarm_name          = "wordpress-rds-cpu-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors rds cpu utilization"
  alarm_actions       = [aws_sns_topic.wordpress_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.wordpress.identifier
  }
}

# SNS Topic for alerts
resource "aws_sns_topic" "wordpress_alerts" {
  name = "wordpress-alerts"

  tags = {
    Name        = "wordpress-alerts"
    Environment = var.environment
    Project     = var.project
  }
}

# Data Sources
data "aws_availability_zones" "available" {
  state = "available"
}

# IAM Role for EC2 Instances
resource "aws_iam_role" "wordpress" {
  name = "wordpress-ec2-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = {
    Name        = "wordpress-ec2-role"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_instance_profile" "wordpress" {
  name = "wordpress-ec2-profile"
  role = aws_iam_role.wordpress.name
}

resource "aws_iam_role_policy" "wordpress_s3_access" {
  name = "wordpress-s3-access"
  role = aws_iam_role.wordpress.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:*"
      ],
      "Effect": "Allow",
      "Resource": "${aws_s3_bucket.wordpress_assets.arn}/*"
    }
  ]
}
EOF
}

# Variables
variable "aws_region" {
  description = "AWS region for resources"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "List of public subnet CIDR blocks"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "List of private subnet CIDR blocks"
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "environment" {
  description = "Environment tag"
  default     = "production"
}

variable "project" {
  description = "Project tag"
  default     = "wordpress"
}

variable "admin_ip_ranges" {
  type        = list(string)
  description = "List of CIDR blocks allowed to access EC2 via SSH"
  default     = ["0.0.0.0/0"] # Note: Use a specific IP range in production
}

variable "ami_id" {
  description = "AMI ID for EC2 instances"
  default     = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 AMI
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t2.micro"
}

variable "key_name" {
  description = "SSH key pair name"
  default     = "my-key-pair"
}

variable "asg_max_size" {
  description = "Maximum size of the Auto Scaling Group"
  default     = 3
}

variable "asg_min_size" {
  description = "Minimum size of the Auto Scaling Group"
  default     = 1
}

variable "db_engine" {
  description = "Database engine type"
  default     = "mysql"
}

variable "db_engine_version" {
  description = "Database engine version"
  default     = "5.7"
}

variable "db_instance_class" {
  description = "Database instance class"
  default     = "db.t2.micro"
}

variable "db_allocated_storage" {
  description = "Database allocated storage in GB"
  default     = 20
}

variable "db_storage_type" {
  description = "Database storage type"
  default     = "gp2"
}

variable "db_name" {
  description = "Database name"
  default     = "wordpressdb"
}

variable "db_username" {
  description = "Database username"
  default     = "admin"
}

variable "db_password" {
  description = "Database password"
  default     = "password123" # Use a secret manager in production
}

variable "db_multi_az" {
  description = "Enable Multi-AZ deployment"
  default     = false
}

variable "db_parameter_group_family" {
  description = "Database parameter group family"
  default     = "mysql5.7"
}

variable "domain_name" {
  description = "Domain name for WordPress site"
  default     = "example.com"
}

# Outputs
output "elb_dns_name" {
  value       = aws_elb.wordpress.dns_name
  description = "DNS name of the Elastic Load Balancer"
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.wordpress.domain_name
  description = "Domain name of the CloudFront distribution"
}

output "s3_bucket_arn" {
  value       = aws_s3_bucket.wordpress_assets.arn
  description = "ARN of the S3 bucket for WordPress assets"
}

output "route53_zone_id" {
  value       = aws_route53_zone.wordpress.zone_id
  description = "Route 53 Hosted Zone ID"
}

output "rds_endpoint" {
  value       = aws_db_instance.wordpress.endpoint
  description = "Endpoint of the RDS instance"
}

output "rds_arn" {
  value       = aws_db_instance.wordpress.arn
  description = "ARN of the RDS instance"
}
