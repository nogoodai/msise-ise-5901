terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Variables
variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks for public subnets"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks for private subnets"
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "ami" {
  description = "Amazon Machine Image ID for EC2 instances"
  default     = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 AMI
}

variable "instance_type" {
  description = "EC2 instance type for WordPress servers"
  default     = "t2.micro"
}

variable "database_instance_class" {
  description = "RDS instance type"
  default     = "db.t2.micro"
}

variable "domain_name" {
  description = "Domain name for the WordPress site"
  default     = "example.com"
}

# Provider configuration for AWS
provider "aws" {
  region = var.region
}

# VPC and networking resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "public_subnets" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name        = "PublicSubnet-${count.index + 1}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name        = "PrivateSubnet-${count.index + 1}"
    Environment = "Production"
    Project     = "WordPress"
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
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table_association" "public_association" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table_association" "private_association" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security groups
resource "aws_security_group" "web_server_sg" {
  name        = "web-server-sg"
  description = "Security group for web servers"
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
    cidr_blocks = ["0.0.0.0/0"] # Should be restricted in production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WebServerSecurityGroup"
    Environment = "Production"
    Project     = "WordPress"
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
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "RDSSecurityGroup"
    Environment = "Production"
    Project     = "WordPress"
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
    Name        = "ELBSecurityGroup"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# EC2 instances for WordPress
resource "aws_launch_configuration" "wordpress_lc" {
  name_prefix   = "wordpress-lc-"
  image_id      = var.ami
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_server_sg.id]

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

resource "aws_autoscaling_group" "wordpress_asg" {
  name                 = "wordpress-asg"
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  min_size             = 1
  max_size             = 3
  desired_capacity     = 2
  vpc_zone_identifier  = aws_subnet.public_subnets[*].id

  tag {
    key                 = "Name"
    value               = "WordPressInstance"
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

# RDS instance for the WordPress database
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private_subnets[*].id
  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = var.database_instance_class
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password123" # Should be stored in AWS Secrets Manager
  parameter_group_name = "default.mysql5.7"
  multi_az             = true
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  skip_final_snapshot  = true

  tags = {
    Name        = "WordPressDatabase"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Elastic Load Balancer
resource "aws_lb" "wordpress_lb" {
  name               = "wordpress-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.elb_sg.id]
  subnets            = aws_subnet.public_subnets[*].id

  tags = {
    Name        = "WordPressLoadBalancer"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.wordpress_lb.arn
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
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    path                = "/"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 30
    interval            = 60
    matcher             = "200"
  }

  tags = {
    Name        = "WordPressTargetGroup"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.wordpress_asg.id
  lb_target_group_arn    = aws_lb_target_group.wordpress_tg.arn
}

# CloudFront distribution for content delivery
resource "aws_s3_bucket" "wordpress_static_assets" {
  bucket = "wordpress-static-assets-${random_id.bucket_suffix.hex}"
  acl    = "private"

  tags = {
    Name        = "WordPressStaticAssets"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket_public_access_block" "block_public_access" {
  bucket = aws_s3_bucket.wordpress_static_assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_s3_bucket.wordpress_static_assets.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.wordpress_static_assets.id}"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.wordpress_static_assets.id}"

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
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Route 53 DNS configuration
data "aws_route53_zone" "selected" {
  name         = var.domain_name
  private_zone = false
}

resource "aws_route53_record" "wordpress_lb" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.wordpress_lb.dns_name
    zone_id                = aws_lb.wordpress_lb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "wordpress_cf" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cf.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cf.hosted_zone_id
    evaluate_target_health = false
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Monitoring and Alerting
resource "aws_cloudwatch_metric_alarm" "wordpress_asg_cpu_alarm" {
  alarm_name          = "wordpress-asg-cpu-alarm"
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
    AutoScalingGroupName = aws_autoscaling_group.wordpress_asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu_utilization" {
  alarm_name          = "rds-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = []
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.wordpress_db.id
  }
}

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
              "AutoScalingGroupName",
              "${aws_autoscaling_group.wordpress_asg.name}"
            ]
          ],
          "view": "timeSeries",
          "stacked": false,
          "region": "${var.region}",
          "title": "EC2 CPU Utilization",
          "period": 300
        }
      },
      {
        "type": "metric",
        "x": 0,
        "y": 6,
        "width": 12,
        "height": 6,
        "properties": {
          "metrics": [
            [
              "AWS/RDS",
              "CPUUtilization",
              "DBInstanceIdentifier",
              "${aws_db_instance.wordpress_db.id}"
            ]
          ],
          "view": "timeSeries",
          "stacked": false,
          "region": "${var.region}",
          "title": "RDS CPU Utilization",
          "period": 300
        }
      }
    ]
  }
EOF
}

# Outputs
output "alb_dns_name" {
  value = aws_lb.wordpress_lb.dns_name
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cf.domain_name
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.wordpress_static_assets.arn
}
