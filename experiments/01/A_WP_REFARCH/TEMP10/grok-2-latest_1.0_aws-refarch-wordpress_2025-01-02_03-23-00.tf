terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Variables
variable "region" {
  description = "AWS region"
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
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

variable "environment" {
  description = "Environment tag"
  default     = "production"
}

variable "project_name" {
  description = "Project name tag"
  default     = "WordPress"
}

variable "allowed_ssh_cidr" {
  description = "Allowed CIDR for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Update this to specific IPs in production
}

variable "rds_instance_class" {
  description = "RDS instance class"
  default     = "db.t2.micro"
}

variable "rds_engine" {
  description = "RDS database engine"
  default     = "mysql"
}

variable "rds_engine_version" {
  description = "RDS database engine version"
  default     = "5.7"
}

variable "ec2_instance_type" {
  description = "EC2 instance type for WordPress"
  default     = "t2.micro"
}

variable "autoscaling_min_size" {
  description = "Minimum size of the Auto Scaling group"
  default     = 1
}

variable "autoscaling_max_size" {
  description = "Maximum size of the Auto Scaling group"
  default     = 3
}

variable "domain_name" {
  description = "Domain name for Route 53"
  default     = "example.com"
}

variable "cloudfront_origin_id" {
  description = "CloudFront origin ID"
  default     = "ALBS3"
}

# Provider Configuration
provider "aws" {
  region = var.region
}

# Data Sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*"]
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
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name        = "${var.project_name}-Public-Subnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name        = "${var.project_name}-Private-Subnet-${count.index + 1}"
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
    Name        = "${var.project_name}-Public-RT"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnets)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "${var.project_name}-Private-RT"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnets)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security Groups
resource "aws_security_group" "web_server" {
  name        = "${var.project_name}-Web-Server-SG"
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
    cidr_blocks = var.allowed_ssh_cidr
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-Web-Server-SG"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-RDS-SG"
  description = "Security group for RDS"
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
    Name        = "${var.project_name}-ELB-SG"
    Environment = var.environment
    Project     = var.project_name
  }
}

# EC2 Instances for WordPress
resource "aws_launch_configuration" "wordpress" {
  name_prefix          = "${var.project_name}-LC-"
  image_id             = data.aws_ami.amazon_linux.id
  instance_type        = var.ec2_instance_type
  security_groups      = [aws_security_group.web_server.id]
  key_name             = aws_key_pair.wordpress.key_name
  user_data            = file("${path.module}/wordpress_user_data.sh")
  iam_instance_profile = aws_iam_instance_profile.wordpress.name

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wordpress" {
  name                = "${var.project_name}-ASG"
  vpc_zone_identifier = aws_subnet.public[*].id
  min_size            = var.autoscaling_min_size
  max_size            = var.autoscaling_max_size
  launch_configuration = aws_launch_configuration.wordpress.name

  tag {
    key                 = "Name"
    value               = "${var.project_name}-Web-Server"
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

# RDS Instance for WordPress
resource "aws_db_subnet_group" "wordpress" {
  name       = "${var.project_name}-DB-Subnet-Group"
  subnet_ids = aws_subnet.private[*].id
  tags = {
    Name        = "${var.project_name}-DB-Subnet-Group"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_db_instance" "wordpress" {
  identifier             = "${var.project_name}-db"
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = var.rds_engine
  engine_version         = var.rds_engine_version
  instance_class         = var.rds_instance_class
  name                   = "wordpressdb"
  username               = "admin"
  password               = "password123" # Use a secret manager in production
  parameter_group_name   = "default.mysql5.7"
  multi_az               = true
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.wordpress.name
  skip_final_snapshot    = true

  tags = {
    Name        = "${var.project_name}-DB"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Elastic Load Balancer
resource "aws_lb" "wordpress" {
  name               = "${var.project_name}-ALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.elb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name        = "${var.project_name}-ALB"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lb_target_group" "wordpress" {
  name     = "${var.project_name}-TG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/wp-admin/install.php"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 30
    interval            = 60
    matcher             = "200"
  }

  tags = {
    Name        = "${var.project_name}-TG"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lb_listener" "wordpress_http" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}

resource "aws_autoscaling_attachment" "asg_attachment_wordpress" {
  autoscaling_group_name = aws_autoscaling_group.wordpress.id
  lb_target_group_arn    = aws_lb_target_group.wordpress.arn
}

# CloudFront Distribution
resource "aws_s3_bucket" "wordpress_static_assets" {
  bucket = "${var.project_name}-static-assets"
  acl    = "private"

  tags = {
    Name        = "${var.project_name}-Static-Assets-Bucket"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_s3_bucket.wordpress_static_assets.bucket_regional_domain_name
    origin_id   = var.cloudfront_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.wordpress.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = var.cloudfront_origin_id

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
    Name        = "${var.project_name}-CloudFront-Distribution"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudfront_origin_access_identity" "wordpress" {
  comment = "${var.project_name}-OAI"
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress" {
  name = var.domain_name

  tags = {
    Name        = "${var.project_name}-Hosted-Zone"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route53_record" "wordpress_alb" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.wordpress.dns_name
    zone_id                = aws_lb.wordpress.zone_id
    evaluate_target_health = true
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

# Key Pair
resource "aws_key_pair" "wordpress" {
  key_name   = "${var.project_name}-key"
  public_key = file("${path.module}/wordpress_key.pub")
}

# IAM Role and Instance Profile for EC2
resource "aws_iam_role" "wordpress" {
  name = "${var.project_name}-EC2-Role"

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
    Name        = "${var.project_name}-EC2-Role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_instance_profile" "wordpress" {
  name = "${var.project_name}-EC2-Instance-Profile"
  role = aws_iam_role.wordpress.name
}

resource "aws_iam_role_policy_attachment" "wordpress_s3" {
  role       = aws_iam_role.wordpress.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# CloudWatch Alarms for EC2 Instances
resource "aws_cloudwatch_metric_alarm" "ec2_cpu_utilization" {
  alarm_name          = "${var.project_name}-EC2-CPU-Utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = []

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.wordpress.name
  }

  tags = {
    Name        = "${var.project_name}-EC2-CPU-Utilization-Alarm"
    Environment = var.environment
    Project     = var.project_name
  }
}

# CloudWatch Alarms for RDS
resource "aws_cloudwatch_metric_alarm" "rds_free_storage_space" {
  alarm_name          = "${var.project_name}-RDS-Free-Storage-Space"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "60"
  statistic           = "Average"
  threshold           = "1000000000" # 1GB
  alarm_description   = "This metric monitors rds free storage space"
  alarm_actions       = []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.wordpress.identifier
  }

  tags = {
    Name        = "${var.project_name}-RDS-Free-Storage-Space-Alarm"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Outputs
output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC"
}

output "public_subnet_ids" {
  value       = aws_subnet.public[*].id
  description = "The IDs of the public subnets"
}

output "private_subnet_ids" {
  value       = aws_subnet.private[*].id
  description = "The IDs of the private subnets"
}

output "alb_dns_name" {
  value       = aws_lb.wordpress.dns_name
  description = "The DNS name of the ALB"
}

output "rds_endpoint" {
  value       = aws_db_instance.wordpress.endpoint
  description = "The endpoint of the RDS instance"
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.wordpress.domain_name
  description = "The domain name of the CloudFront distribution"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.wordpress_static_assets.id
  description = "The name of the S3 bucket for static assets"
}

output "route53_zone_id" {
  value       = aws_route53_zone.wordpress.zone_id
  description = "The ID of the Route 53 hosted zone"
}
