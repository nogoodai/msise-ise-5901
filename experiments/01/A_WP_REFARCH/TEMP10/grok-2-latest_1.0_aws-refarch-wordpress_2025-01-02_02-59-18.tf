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

variable "public_subnets_cidr" {
  type        = list(string)
  description = "CIDR blocks for public subnets"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets_cidr" {
  type        = list(string)
  description = "CIDR blocks for private subnets"
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  type        = list(string)
  description = "List of availability zones"
  default     = ["us-west-2a", "us-west-2b"]
}

variable "ssh_allowed_ips" {
  type        = list(string)
  description = "List of CIDR blocks allowed to SSH into the instances"
  default     = ["0.0.0.0/0"]
}

variable "domain_name" {
  description = "Domain name for the WordPress site"
  default     = "example.com"
}

variable "database_instance_class" {
  description = "RDS instance class"
  default     = "db.t2.micro"
}

variable "elasticache_node_type" {
  description = "ElastiCache node type"
  default     = "cache.t2.micro"
}

variable "efs_performance_mode" {
  description = "EFS performance mode"
  default     = "generalPurpose"
}

variable "wordpress_ami" {
  description = "AMI ID for WordPress EC2 instances"
  default     = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 AMI
}

variable "instance_type" {
  description = "EC2 instance type for WordPress"
  default     = "t2.micro"
}

variable "asg_min_size" {
  description = "Minimum size of Auto Scaling Group"
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum size of Auto Scaling Group"
  default     = 3
}

variable "asg_desired_capacity" {
  description = "Desired capacity of Auto Scaling Group"
  default     = 1
}

# Provider Configuration
provider "aws" {
  region = var.region
}

# VPC and Networking Resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPress-VPC"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPress-IGW"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "public" {
  count             = length(var.public_subnets_cidr)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnets_cidr[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "WordPress-Public-Subnet-${count.index + 1}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnets_cidr)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnets_cidr[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "WordPress-Private-Subnet-${count.index + 1}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name        = "WordPress-Public-Route-Table"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnets_cidr)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPress-Private-Route-Table"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnets_cidr)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security Groups
resource "aws_security_group" "web_server" {
  name        = "wordpress-web-server-sg"
  description = "Allow inbound traffic for WordPress"
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
    cidr_blocks = var.ssh_allowed_ips
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WordPress-Web-Server-SG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "database" {
  name        = "wordpress-database-sg"
  description = "Allow inbound traffic for RDS"
  vpc_id      = aws_vpc.wordpress_vpc.id

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
    Name        = "WordPress-Database-SG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "elb" {
  name        = "wordpress-elb-sg"
  description = "Allow inbound traffic for ELB"
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
    Name        = "WordPress-ELB-SG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# EC2 Instances for WordPress
resource "aws_launch_configuration" "wordpress" {
  name_prefix          = "wordpress-"
  image_id             = var.wordpress_ami
  instance_type        = var.instance_type
  security_groups      = [aws_security_group.web_server.id]
  key_name             = aws_key_pair.wordpress_key.key_name
  user_data            = file("user_data.sh") # User data script for WordPress installation
  iam_instance_profile = aws_iam_instance_profile.wordpress_profile.name

  lifecycle {
    create_before_destroy = true
  }
}

# RDS Instance for WordPress Database
resource "aws_db_instance" "wordpress" {
  identifier             = "wordpress-db"
  engine                 = "mysql"
  engine_version         = "5.7"
  instance_class         = var.database_instance_class
  allocated_storage      = 20
  storage_type           = "gp2"
  db_name                = "wordpressdb"
  username               = "admin"
  password               = "yourpasswordhere" # Use a secret manager or environment variable in production
  vpc_security_group_ids = [aws_security_group.database.id]
  multi_az               = true
  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.wordpress.name
  skip_final_snapshot    = true

  tags = {
    Name        = "WordPress-RDS"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_db_subnet_group" "wordpress" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "WordPress-DB-Subnet-Group"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Elastic Load Balancer
resource "aws_lb" "wordpress" {
  name               = "wordpress-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.elb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name        = "WordPress-ELB"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}

resource "aws_lb_target_group" "wordpress" {
  name     = "wordpress-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    path                = "/"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 30
    interval            = 60
    matcher             = "200"
  }
}

# Auto Scaling Group for EC2 Instances
resource "aws_autoscaling_group" "wordpress" {
  name                 = "wordpress-asg"
  max_size             = var.asg_max_size
  min_size             = var.asg_min_size
  desired_capacity     = var.asg_desired_capacity
  vpc_zone_identifier  = aws_subnet.public[*].id
  launch_configuration = aws_launch_configuration.wordpress.name
  target_group_arns    = [aws_lb_target_group.wordpress.arn]

  tag {
    key                 = "Name"
    value               = "WordPress-Web-Server"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "Production"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = "WordPress"
    propagate_at_launch = true
  }
}

# CloudFront Distribution for Content Delivery
resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_lb.wordpress.dns_name
    origin_id   = "ALB-Origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for WordPress"
  default_root_object = "index.php"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ALB-Origin"

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
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
    Name        = "WordPress-CloudFront"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# S3 Bucket for Static Assets
resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${var.domain_name}"
  acl    = "private"

  tags = {
    Name        = "WordPress-Assets-Bucket"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket_public_access_block" "wordpress_assets" {
  bucket = aws_s3_bucket.wordpress_assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress" {
  name = var.domain_name
}

resource "aws_route53_record" "wordpress_alb" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.wordpress.dns_name
    zone_id                = aws_lb.wordpress.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "wordpress_cloudfront" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress.hosted_zone_id
    evaluate_target_health = false
  }
}

# IAM Role and Instance Profile for EC2 Instances
resource "aws_iam_role" "wordpress_role" {
  name = "wordpress-ec2-role"

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
    Name        = "WordPress-EC2-Role"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_iam_instance_profile" "wordpress_profile" {
  name = "wordpress-ec2-profile"
  role = aws_iam_role.wordpress_role.name
}

resource "aws_iam_role_policy_attachment" "wordpress_s3_access" {
  role       = aws_iam_role.wordpress_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# Key Pair for EC2 Instances
resource "aws_key_pair" "wordpress_key" {
  key_name   = "wordpress-key"
  public_key = file("~/.ssh/id_rsa.pub") # Replace with your public key path
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  alarm_name          = "wordpress-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "This metric monitors EC2 instance CPU utilization"
  alarm_actions       = []

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.wordpress.name
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu_utilization" {
  alarm_name          = "wordpress-rds-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "This metric monitors RDS instance CPU utilization"
  alarm_actions       = []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.wordpress.identifier
  }
}

# Outputs
output "wordpress_vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "wordpress_alb_dns_name" {
  value = aws_lb.wordpress.dns_name
}

output "wordpress_cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress.domain_name
}

output "wordpress_rds_endpoint" {
  value = aws_db_instance.wordpress.endpoint
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_assets.id
}

output "wordpress_route53_zone_id" {
  value = aws_route53_zone.wordpress.zone_id
}
