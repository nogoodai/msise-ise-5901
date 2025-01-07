# Configuration for AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Provider configuration
provider "aws" {
  region = "us-west-2"
}

# Variables for user-configurable values
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "The availability zones for the subnets"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "The instance type for the EC2 instances"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "The instance class for the RDS instance"
}

variable "elasticache_node_type" {
  type        = string
  default     = "cache.t2.micro"
  description = "The node type for the Elasticache cluster"
}

variable "cloudfront_ssl_certificate_arn" {
  type        = string
  description = "The ARN of the SSL certificate for the CloudFront distribution"
}

# Networking resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_subnet" "public_subnets" {
  count = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PublicSubnet${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, length(var.availability_zones) + count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PrivateSubnet${count.index + 1}"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table_association" "public_subnets" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnets" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security groups
resource "aws_security_group" "web_server_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
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
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "WebServerSG"
  }
}

resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
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
    Name = "RDSSG"
  }
}

# EC2 instances for WordPress
resource "aws_instance" "wordpress_ec2" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.web_server_sg.id
  ]
  subnet_id = aws_subnet.public_subnets[0].id
  key_name               = "wordpress_key"
  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              sudo apt-get install -y apache2 php libapache2-mod-php mysql-server
              sudo systemctl start apache2
              sudo systemctl enable apache2
              EOF
  tags = {
    Name = "WordPressEC2"
  }
}

# RDS instance for the WordPress database
resource "aws_db_instance" "wordpress_rds" {
  identifier        = "wordpress-rds"
  instance_class    = var.rds_instance_class
  engine            = "mysql"
  engine_version   = "8.0.28"
  allocated_storage = 20
  storage_type      = "gp2"
  username          = "admin"
  password          = "password"
  publicly_accessible = false
  vpc_security_group_ids = [
    aws_security_group.rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  tags = {
    Name = "WordPressRDS"
  }
}

resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = aws_subnet.private_subnets.*.id
  tags = {
    Name = "WordPressRDSSubnetGroup"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name               = "wordpress-elb"
  subnets            = aws_subnet.public_subnets.*.id
  security_groups = [
    aws_security_group.web_server_sg.id
  ]
  listener {
    lb_port       = 80
    lb_protocol   = "http"
    instance_port = 80
    instance_protocol = "http"
  }
  listener {
    lb_port       = 443
    lb_protocol   = "https"
    instance_port = 80
    instance_protocol = "http"
  }
  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    unhealthy_threshold = 2
    healthy_threshold   = 2
  }
  tags = {
    Name = "WordPressELB"
  }
}

# Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  min_size                  = 1
  max_size                  = 3
  desired_capacity          = 2
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  tag {
    key                 = "Name"
    value               = "WordPressASG"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              sudo apt-get install -y apache2 php libapache2-mod-php mysql-server
              sudo systemctl start apache2
              sudo systemctl enable apache2
              EOF
  security_groups = [
    aws_security_group.web_server_sg.id
  ]
  key_name = "wordpress_key"
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cf" {
  alias             = "wordpress.example.com"
  enabled           = true
  is_ipv6_enabled   = true
  default_root_object = "index.html"
  custom_error_response {
    error_caching_min_ttl = 0
    error_code            = 404
    response_code         = 200
    response_page_path    = "/404.html"
  }
  ordered_cache_behavior {
    path_pattern     = "/wp-content/*"
    target_origin_id = "wordpress-origin"
    forwarded_values {
      query_string = false
      headers {
        items = ["Origin"]
      }
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-origin"
    custom_header {
      name  = "Host"
      value = "wordpress.example.com"
    }
  }
  restrictions {
    geo_restriction {
      locations        = ["US", "CA", "GB", "DE"]
      restriction_type = "whitelist"
    }
  }
  viewer_certificate {
    acm_certificate_arn = var.cloudfront_ssl_certificate_arn
    ssl_support_method  = "sni-only"
  }
  depends_on = [aws_elb.wordpress_elb]
}

# S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_s3" {
  bucket = "wordpress.example.com"
  acl    = "private"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource = [
          aws_s3_bucket.wordpress_s3.arn,
          "${aws_s3_bucket.wordpress_s3.arn}/*",
        ]
      },
    ]
  })
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
}

# Route 53 DNS configuration
resource "aws_route53_record" "wordpress_dns" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "wordpress.example.com"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cf.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cf.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
}

# CloudWatch alarms
resource "aws_cloudwatch_metric_alarm" "wordpress_cpu_alarm" {
  alarm_name          = "wordpress-cpu-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  actions_enabled     = true
  alarm_actions       = [aws_sns_topic.wordpress_sns_topic.arn]
  ok_actions          = [aws_sns_topic.wordpress_sns_topic.arn]
  insufficient_data_actions = [aws_sns_topic.wordpress_sns_topic.arn]
  dimensions = {
    InstanceId = aws_instance.wordpress_ec2.id
  }
}

resource "aws_cloudwatch_metric_alarm" "wordpress_rds_alarm" {
  alarm_name          = "wordpress-rds-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 100
  actions_enabled     = true
  alarm_actions       = [aws_sns_topic.wordpress_sns_topic.arn]
  ok_actions          = [aws_sns_topic.wordpress_sns_topic.arn]
  insufficient_data_actions = [aws_sns_topic.wordpress_sns_topic.arn]
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.wordpress_rds.id
  }
}

resource "aws_sns_topic" "wordpress_sns_topic" {
  name = "wordpress-sns-topic"
}

# Elasticache cluster
resource "aws_elasticache_cluster" "wordpress_elasticache" {
  cluster_id           = "wordpress-elasticache"
  engine               = "memcached"
  node_type            = var.elasticache_node_type
  num_cache_nodes       = 1
  parameter_group_name = "default.memcached1.4"
  port                 = 11211
  security_group_ids = [
    aws_security_group.web_server_sg.id
  ]
  subnet_group_name = aws_elasticache_subnet_group.wordpress_elasticache_subnet_group.name
}

resource "aws_elasticache_subnet_group" "wordpress_elasticache_subnet_group" {
  name       = "wordpress-elasticache-subnet-group"
  subnet_ids = aws_subnet.private_subnets.*.id
}

# EFS file system
resource "aws_efs_file_system" "wordpress_efs" {
  creation_token = "wordpress-efs"
  encrypted      = true
  performance_mode = "generalPurpose"
  throughput_mode  = "provisioned"
  provisioned_throughput_in_mibps = 10
}

resource "aws_efs_mount_target" "wordpress_efs_mount_target" {
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = aws_subnet.private_subnets[0].id
  security_groups = [
    aws_security_group.web_server_sg.id
  ]
}

# Outputs
output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3.bucket
}

output "wordpress_cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cf.domain_name
}

output "wordpress_route53_record_name" {
  value = aws_route53_record.wordpress_dns.name
}
