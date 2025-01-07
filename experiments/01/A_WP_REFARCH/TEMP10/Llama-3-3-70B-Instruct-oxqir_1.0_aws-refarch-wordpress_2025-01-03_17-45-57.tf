# Terraform configuration for AWS resources

# Configure the AWS provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
}

# Variables for user-configurable values
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnets" {
  default = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnets" {
  default = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

variable "web_server_instance_type" {
  default = "t2.micro"
}

variable "db_instance_class" {
  default = "db.t2.small"
}

variable "wordpress_bucket_name" {
  default = "wordpress-static-assets"
}

variable "cloudfront_distribution_name" {
  default = "wordpress-cdn"
}

variable "route53_hosted_zone_name" {
  default = "example.com"
}

# VPC configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

# Networking resources
resource "aws_subnet" "public" {
  count = length(var.public_subnets)

  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = var.public_subnets[count.index]
  availability_zone = "us-west-2${count.index + 1}"
  tags = {
    Name = "PublicSubnet${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count = length(var.private_subnets)

  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = var.private_subnets[count.index]
  availability_zone = "us-west-2${count.index + 1}"
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

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table_association" "public" {
  count = length(var.public_subnets)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name = "PrivateRouteTable"
  }
}

resource "aws_route_table_association" "private" {
  count = length(var.private_subnets)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security groups for EC2 instances, RDS, and ELB
resource "aws_security_group" "web_server_sg" {
  name        = "WordPressWebServerSG"
  description = "Security group for WordPress web servers"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
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
    Name = "WordPressWebServerSG"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "WordPressRDSSG"
  description = "Security group for WordPress RDS"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "WordPressRDSSG"
  }
}

resource "aws_security_group" "elb_sg" {
  name        = "WordPressELBSG"
  description = "Security group for WordPress ELB"
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
    Name = "WordPressELBSG"
  }
}

# EC2 instances for WordPress
resource "aws_instance" "wordpress" {
  count = 3

  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.web_server_instance_type
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  subnet_id = aws_subnet.public[count.index].id
  tags = {
    Name = "WordPressInstance${count.index + 1}"
  }
}

# RDS instance for the WordPress database
resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = var.db_instance_class
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password123"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnets.name
}

resource "aws_db_subnet_group" "wordpress_db_subnets" {
  name       = "wordpress-dbsubnetgroup"
  subnet_ids = [for subnet in aws_subnet.private : subnet.id]

  tags = {
    Name = "WordPressDBSubnetGroup"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = [for subnet in aws_subnet.public : subnet.id]
  security_groups = [aws_security_group.elb_sg.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  listener {
    instance_port      = 443
    instance_protocol  = "https"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  }

  tags = {
    Name = "WordPressELB"
  }
}

# Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "wordpress-asg"
  max_size            = 5
  min_size            = 3
  health_check_grace_period = 300
  health_check_type         = "ELB"
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = [for subnet in aws_subnet.public : subnet.id]

  tag {
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.web_server_instance_type
  security_groups = [aws_security_group.web_server_sg.id]
  user_data = "#!/bin/bash\nsudo apt-get update -y\nsudo apt-get install -y apache2\nsudo service apache2 start"

  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront distribution for content delivery
resource "aws_cloudfront_distribution" "wordpress_cloudfront" {
  origin {
    domain_name = aws_s3_bucket.wordpress_bucket.bucket_regional_domain_name
    origin_id   = "wordpress-s3-origin"

    custom_header {
      name  = "User-Agent"
      value = "CloudFront"
    }
  }

  enabled         = true
  default_root_object = "index.html"
  aliases = ["example.com", "www.example.com"]

  viewer_certificate {
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method = "sni-only"
  }
}

# S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = var.wordpress_bucket_name
  acl    = "private"

  tags = {
    Name        = "WordPressS3Bucket"
    Environment = "Prod"
  }
}

# Route 53 DNS configuration
resource "aws_route53_record" "wordpress_a_record" {
  zone_id = aws_route53_zone.wordpress_hosted_zone.zone_id
  name    = var.route53_hosted_zone_name
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "wordpress_hosted_zone" {
  name = var.route53_hosted_zone_name
}

# CloudWatch alarms for key metrics
resource "aws_cloudwatch_metric_alarm" "wordpress_alarm" {
  alarm_name                = "WordPressAlarm"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = "2"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "300"
  statistic                  = "Average"
  threshold                 = "70"
  alarm_description         = "CPU utilization exceeds 70% for 5 minutes"
  actions_enabled           = true
  alarm_actions             = [aws_sns_topic.wordpress_sns_topic.arn]

  metric_query {
    id          = "metric1"
    metric {
      metric_name = "CPUUtilization"
      namespace   = "AWS/EC2"
      period      = "300"
      stat        = "Average"
      unit        = "Percent"
    }
  }
}

resource "aws_sns_topic" "wordpress_sns_topic" {
  name = "WordPressSNSTopic"
}
