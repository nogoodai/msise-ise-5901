provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type        = string
  default     = "us-west-2"
  description = "AWS Region"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "VPC CIDR block"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "List of availability zones"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for EC2 instances"
}

variable "db_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Instance class for RDS instance"
}

variable "wordpress_version" {
  type        = string
  default     = "latest"
  description = "WordPress version"
}

# VPC Configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

# Subnets Configuration
resource "aws_subnet" "public_subnets" {
  count             = 3
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PublicSubnet-${count.index}"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = 3
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 3 + count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PrivateSubnet-${count.index}"
  }
}

# Internet Gateway Configuration
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Route Tables Configuration
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

# Route Configuration
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Subnet Route Table Association Configuration
resource "aws_route_table_association" "public_subnets_association" {
  count          = 3
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnets_association" {
  count          = 3
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security Groups Configuration
resource "aws_security_group" "wordpress_ec2_sg" {
  name        = "WordPressEC2SG"
  description = "Security group for WordPress EC2 instances"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
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
    Name = "WordPressEC2SG"
  }
}

resource "aws_security_group" "wordpress_rds_sg" {
  name        = "WordPressRDSSG"
  description = "Security group for WordPress RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_ec2_sg.id]
  }
  tags = {
    Name = "WordPressRDSSG"
  }
}

resource "aws_security_group" "wordpress_alb_sg" {
  name        = "WordPressALBSG"
  description = "Security group for WordPress ALB"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
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
    Name = "WordPressALBSG"
  }
}

# EC2 Instances Configuration
resource "aws_instance" "wordpress_instance" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public_subnets[0].id
  vpc_security_group_ids = [
    aws_security_group.wordpress_ec2_sg.id
  ]
  tags = {
    Name = "WordPressInstance"
  }
}

# RDS Instance Configuration
resource "aws_db_instance" "wordpress_rds" {
  instance_class    = var.db_instance_class
  engine            = "mysql"
  engine_version    = "8.0.23"
  db_name           = "wordpressdb"
  username          = "wordpressuser"
  password          = "wordpresspassword"
  vpc_security_group_ids = [
    aws_security_group.wordpress_rds_sg.id
  ]
  multi_az = true
  tags = {
    Name = "WordPressRDS"
  }
}

# Elastic Load Balancer Configuration
resource "aws_alb" "wordpress_alb" {
  name            = "WordPressALB"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_alb_sg.id]
  tags = {
    Name = "WordPressALB"
  }
}

resource "aws_alb_target_group" "wordpress_alb_tg" {
  name     = "WordPressALBTG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressALBTG"
  }
}

resource "aws_alb_listener" "wordpress_alb_listener" {
  load_balancer_arn = aws_alb.wordpress_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.wordpress_alb_tg.arn
    type             = "forward"
  }
}

# Auto Scaling Group Configuration
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "WordPressASG"
  max_size            = 3
  min_size            = 1
  desired_capacity    = 1
  health_check_grace_period = 300
  health_check_type           = "EC2"
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id
  tags = {
    Name = "WordPressASG"
  }
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.wordpress_ec2_sg.id
  ]
  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y apache2
              apt-get install -y php libapache2-mod-php
              apt-get install -y mysql-server
              service apache2 restart
              EOF
}

# CloudFront Distribution Configuration
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = "WordPressALB"
  }
  enabled = true
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WordPressALB"
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
    acm_certificate_arn = aws_acm_certificate.wordpress_acm.arn
    ssl_support_method  = "sni-only"
  }
  tags = {
    Name = "WordPressCFD"
  }
}

resource "aws_acm_certificate" "wordpress_acm" {
  domain_name       = "example.com"
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

# S3 Bucket Configuration
resource "aws_s3_bucket" "wordpress_s3" {
  bucket = "wordpress-static-assets"
  acl    = "private"
  tags = {
    Name = "WordPressS3"
  }
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress_r53" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress_r53_alb" {
  zone_id = aws_route53_zone.wordpress_r53.zone_id
  name    = "example.com"
  type    = "A"
  alias {
    name                   = aws_alb.wordpress_alb.dns_name
    zone_id               = aws_alb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "wordpress_r53_cfd" {
  zone_id = aws_route53_zone.wordpress_r53.zone_id
  name    = "example.com"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cfd.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cfd.zone_id
    evaluate_target_health = true
  }
}

# CloudWatch Metrics Configuration
resource "aws_cloudwatch_metric_alarm" "wordpress_cw_alarm" {
  alarm_name                = "WordPressCWAlarm"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = "2"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "300"
  statistic                 = "Average"
  threshold                 = "80"
  alarm_description         = "This metric alarm monitors EC2 instance CPU utilization"
  actions_enabled           = true
  alarm_actions             = [aws_sns_topic.wordpress_sns.arn]
  ok_actions                = [aws_sns_topic.wordpress_sns.arn]
  insufficient_data_actions = [aws_sns_topic.wordpress_sns.arn]
}

resource "aws_sns_topic" "wordpress_sns" {
  name = "WordPressSNS"
}

# Output Configuration
output "alb_dns_name" {
  value = aws_alb.wordpress_alb.dns_name
}

output "rds_instance_address" {
  value = aws_db_instance.wordpress_rds.address
}

output "ec2_instance_id" {
  value = aws_instance.wordpress_instance.id
}

output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cfd.domain_name
}
