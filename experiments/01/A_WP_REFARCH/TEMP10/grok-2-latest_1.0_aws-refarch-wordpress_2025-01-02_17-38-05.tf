terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Provider Configuration
provider "aws" {
  region = var.aws_region
}

# VPC and Networking Resources
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr_block
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

resource "aws_subnet" "public_subnet" {
  count             = length(var.public_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "public-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "private_subnet" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "private-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name        = "public-rt"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table_association" "public_1_rt_association" {
  count          = length(var.public_subnets)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "private-rt"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table_association" "private_1_rt_association" {
  count          = length(var.private_subnets)
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

# Security Groups
resource "aws_security_group" "web_server_sg" {
  name        = "web-server-sg"
  description = "Security group for web servers"
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
    cidr_blocks = var.admin_cidr_blocks
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

resource "aws_security_group" "database_sg" {
  name        = "database-sg"
  description = "Security group for database"
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
    Name        = "database-sg"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group" "elb_sg" {
  name        = "elb-sg"
  description = "Security group for ELB"
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
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_launch_configuration" "wp_lc" {
  name_prefix          = "wp-lc-"
  image_id             = data.aws_ami.amazon_linux.id
  instance_type        = var.instance_type
  security_groups      = [aws_security_group.web_server_sg.id]
  iam_instance_profile = aws_iam_instance_profile.wp_instance_profile.name

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd php php-mysqlnd
              systemctl start httpd
              systemctl enable httpd
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wp_asg" {
  name                 = "wp-asg"
  max_size             = var.asg_max_size
  min_size             = var.asg_min_size
  health_check_type    = "ELB"
  load_balancers       = [aws_elb.wp_elb.name]
  vpc_zone_identifier  = aws_subnet.public_subnet[*].id
  launch_configuration = aws_launch_configuration.wp_lc.name

  tag {
    key                 = "Name"
    value               = "wp-asg-instance"
    propagate_at_launch = true
  }
}

# RDS Instance for WordPress Database
resource "aws_db_instance" "wp_db" {
  allocated_storage     = var.db_allocated_storage
  engine                = var.db_engine
  engine_version        = var.db_engine_version
  instance_class        = var.db_instance_class
  name                  = var.db_name
  username              = var.db_username
  password              = var.db_password
  parameter_group_name  = var.db_parameter_group_name
  skip_final_snapshot   = true
  multi_az              = var.db_multi_az
  vpc_security_group_ids = [aws_security_group.database_sg.id]
  db_subnet_group_name  = aws_db_subnet_group.wp_db_subnet_group.name

  tags = {
    Name        = "wp-db"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_db_subnet_group" "wp_db_subnet_group" {
  name       = "wp-db-subnet-group"
  subnet_ids = aws_subnet.private_subnet[*].id

  tags = {
    Name        = "wp-db-subnet-group"
    Environment = var.environment
    Project     = var.project
  }
}

# Elastic Load Balancer
resource "aws_elb" "wp_elb" {
  name               = "wp-elb"
  subnets            = aws_subnet.public_subnet[*].id
  security_groups    = [aws_security_group.elb_sg.id]
  instances          = aws_autoscaling_group.wp_asg.instances

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
    Name        = "wp-elb"
    Environment = var.environment
    Project     = var.project
  }
}

# CloudFront Distribution for Content Delivery
resource "aws_cloudfront_distribution" "wp_cf" {
  origin {
    domain_name = aws_elb.wp_elb.dns_name
    origin_id   = "wp-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wp-origin"

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
    Name        = "wp-cloudfront"
    Environment = var.environment
    Project     = var.project
  }
}

# S3 Bucket for Static Assets
resource "aws_s3_bucket" "wp_static_assets" {
  bucket = "wp-static-assets-${var.environment}-${var.project}"
  acl    = "private"

  tags = {
    Name        = "wp-static-assets"
    Environment = var.environment
    Project     = var.project
  }
}

# Route 53 DNS Configuration
data "aws_route53_zone" "selected" {
  name         = var.domain_name
  private_zone = false
}

resource "aws_route53_record" "wp_elb_record" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "wp.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_elb.wp_elb.dns_name
    zone_id                = aws_elb.wp_elb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "wp_cf_record" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "cdn.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wp_cf.domain_name
    zone_id                = aws_cloudfront_distribution.wp_cf.hosted_zone_id
    evaluate_target_health = false
  }
}

# Monitoring and Alerting with CloudWatch
resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  alarm_name          = "cpu-utilization-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_sns_topic.notification_topic.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.wp_asg.name
  }
}

resource "aws_sns_topic" "notification_topic" {
  name = "wp-notification-topic"
}

# Outputs
output "elb_dns_name" {
  value = aws_elb.wp_elb.dns_name
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wp_cf.domain_name
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.wp_static_assets.arn
}

output "db_instance_address" {
  value = aws_db_instance.wp_db.address
}

output "db_instance_arn" {
  value = aws_db_instance.wp_db.arn
}

# Variables
variable "aws_region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "List of public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  description = "List of private subnets"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "environment" {
  description = "Environment tag"
  default     = "production"
}

variable "project" {
  description = "Project tag"
  default     = "wordpress"
}

variable "admin_cidr_blocks" {
  description = "CIDR blocks for admin access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t2.micro"
}

variable "asg_max_size" {
  description = "Max size of ASG"
  default     = 3
}

variable "asg_min_size" {
  description = "Min size of ASG"
  default     = 1
}

variable "db_allocated_storage" {
  description = "Allocated storage for the DB instance"
  default     = 20
}

variable "db_engine" {
  description = "Database engine"
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
  sensitive   = true
  default     = "password123"
}

variable "db_parameter_group_name" {
  description = "Database parameter group name"
  default     = "default.mysql5.7"
}

variable "db_multi_az" {
  description = "Enable multi-AZ deployment"
  default     = false
}

variable "domain_name" {
  description = "Domain name for Route 53"
  default     = "example.com"
}

# IAM Instance Profile for EC2 Instances
resource "aws_iam_role" "wp_instance_role" {
  name = "wp_instance_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "wp-instance-role"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_instance_profile" "wp_instance_profile" {
  name = "wp_instance_profile"
  role = aws_iam_role.wp_instance_role.name
}

resource "aws_iam_role_policy" "wp_instance_policy" {
  name = "wp_instance_policy"
  role = aws_iam_role.wp_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.wp_static_assets.arn}/*"
      },
      {
        Action   = "efs:*"
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}
