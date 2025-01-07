# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# AWS provider configuration
provider "aws" {
  region = var.aws_region
}

# VPC configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = var.vpc_name
    Environment = var.environment
    Project     = var.project
  }
}

# Public subnets
resource "aws_subnet" "public_subnets" {
  count = var.public_subnets_count

  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.vpc_name}-public-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project
  }
}

# Private subnets
resource "aws_subnet" "private_subnets" {
  count = var.private_subnets_count

  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, count.index + var.public_subnets_count)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "${var.vpc_name}-private-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project
  }
}

# Internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = var.igw_name
    Environment = var.environment
    Project     = var.project
  }
}

# Public route table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }

  tags = {
    Name        = "${var.vpc_name}-public-route-table"
    Environment = var.environment
    Project     = var.project
  }
}

# Private route table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "${var.vpc_name}-private-route-table"
    Environment = var.environment
    Project     = var.project
  }
}

# Route table associations for public subnets
resource "aws_route_table_association" "public_route_table_associations" {
  count = var.public_subnets_count

  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Route table associations for private subnets
resource "aws_route_table_association" "private_route_table_associations" {
  count = var.private_subnets_count

  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security groups
resource "aws_security_group" "webserver_sg" {
  name        = var.webserver_sg_name
  description = "Security group for webserver"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
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
    Name        = var.webserver_sg_name
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group" "rds_sg" {
  name        = var.rds_sg_name
  description = "Security group for RDS"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "MySQL from webserver"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.webserver_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = var.rds_sg_name
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group" "elb_sg" {
  name        = var.elb_sg_name
  description = "Security group for ELB"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
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
    Name        = var.elb_sg_name
    Environment = var.environment
    Project     = var.project
  }
}

# EC2 instance for WordPress
resource "aws_instance" "wordpress_instance" {
  ami           = var.wordpress_ami
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.webserver_sg.id]
  subnet_id = aws_subnet.public_subnets[0].id

  tags = {
    Name        = var.instance_name
    Environment = var.environment
    Project     = var.project
  }
}

# RDS instance for WordPress database
resource "aws_db_instance" "wordpress_db" {
  identifier        = var.db_identifier
  engine            = var.db_engine
  engine_version    = var.db_engine_version
  instance_class    = var.db_instance_class
  multi_az          = var.db_multi_az
  username          = var.db_username
  password          = var.db_password
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name

  tags = {
    Name        = var.db_identifier
    Environment = var.environment
    Project     = var.project
  }
}

# DB subnet group
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = var.db_subnet_group_name
  subnet_ids = aws_subnet.private_subnets.*.id

  tags = {
    Name        = var.db_subnet_group_name
    Environment = var.environment
    Project     = var.project
  }
}

# Elastic Load Balancer
resource "aws_lb" "wordpress_elb" {
  name               = var.elb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.elb_sg.id]
  subnets            = aws_subnet.public_subnets.*.id

  depends_on = [aws_internet_gateway.wordpress_igw]

  tags = {
    Name        = var.elb_name
    Environment = var.environment
    Project     = var.project
  }
}

# Target group for ELB
resource "aws_lb_target_group" "wordpress_target_group" {
  name     = var.target_group_name
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    interval            = 30
    path                = "/"
    port                = 80
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name        = var.target_group_name
    Environment = var.environment
    Project     = var.project
  }
}

# Listener for ELB
resource "aws_lb_listener" "wordpress_listener" {
  load_balancer_arn = aws_lb.wordpress_elb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.wordpress_target_group.arn
    type             = "forward"
  }
}

# Attachment for target group
resource "aws_lb_target_group_attachment" "wordpress_attachment" {
  target_group_arn = aws_lb_target_group.wordpress_target_group.arn
  target_id        = aws_instance.wordpress_instance.id
  port             = 80
}

# Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = var.asg_name
  max_size            = var.asg_max_size
  min_size            = var.asg_min_size
  desired_capacity    = var.asg_desired_capacity
  health_check_type    = "EC2"
  launch_configuration = aws_launch_configuration.wordpress_launch_config.name
  vpc_zone_identifier  = aws_subnet.public_subnets[0].id

  tag {
    key                 = "Name"
    value               = var.instance_name
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

# Launch configuration for Auto Scaling Group
resource "aws_launch_configuration" "wordpress_launch_config" {
  name          = var.launch_config_name
  image_id      = var.wordpress_ami
  instance_type = var.instance_type
  user_data     = templatefile("wordpress_userdata.tpl", {
    db_host = aws_db_instance.wordpress_db.address,
    db_user = var.db_username,
    db_password = var.db_password,
    db_name = var.db_name,
    domain_name = var.domain_name
  })
  security_groups = [aws_security_group.webserver_sg.id]

  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_lb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"

    custom_origin_config {
      http_port              = 80
      https_port            = 443
      origin_protocol_policy = "match-viewer"
      origin_ssl_protocols   = ["SSLv3", "TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = var.distribution_comment
  default_root_object = "index.html"

  aliases = [var.domain_name]

  custom_error_response {
    error_caching_min_ttl = 0
    error_code            = 404
    response_code        = 200
    response_page_path    = "/index.html"
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate_validation.wordpress_cert.certificate_arn
    ssl_support_method       = "sni-only"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name        = var.distribution_name
    Environment = var.environment
    Project     = var.project
  }
}

# ACM certificate
resource "aws_acm_certificate" "wordpress_cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  tags = {
    Name        = var.certificate_name
    Environment = var.environment
    Project     = var.project
  }
}

# ACM certificate validation
resource "aws_acm_certificate_validation" "wordpress_cert" {
  certificate_arn = aws_acm_certificate.wordpress_cert.arn
  validation_record {
    name    = aws_acm_certificate.wordpress_cert.domain_validation_options[0].resource_record_name
    type    = aws_acm_certificate.wordpress_cert.domain_validation_options[0].resource_record_type
    value   = aws_acm_certificate.wordpress_cert.domain_validation_options[0].resource_record_value
  }
}

# Route 53 zone
resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name

  tags = {
    Name        = var.zone_name
    Environment = var.environment
    Project     = var.project
  }
}

# Route 53 record for ELB
resource "aws_route53_record" "wordpress_elb_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.wordpress_elb.dns_name
    zone_id               = aws_lb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

# S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = var.bucket_name

  acl           = "private"
  force_destroy = true

  tags = {
    Name        = var.bucket_name
    Environment = var.environment
    Project     = var.project
  }
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region"
}

variable "vpc_name" {
  type        = string
  default     = "wordpress-vpc"
  description = "VPC name"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "VPC CIDR block"
}

variable "public_subnets_count" {
  type        = number
  default     = 2
  description = "Number of public subnets"
}

variable "private_subnets_count" {
  type        = number
  default     = 2
  description = "Number of private subnets"
}

variable "webserver_sg_name" {
  type        = string
  default     = "wordpress-webserver-sg"
  description = "Web server security group name"
}

variable "rds_sg_name" {
  type        = string
  default     = "wordpress-rds-sg"
  description = "RDS security group name"
}

variable "elb_sg_name" {
  type        = string
  default     = "wordpress-elb-sg"
  description = "ELB security group name"
}

variable "instance_name" {
  type        = string
  default     = "wordpress-instance"
  description = "Instance name"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type"
}

variable "wordpress_ami" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
  description = "WordPress AMI ID"
}

variable "db_identifier" {
  type        = string
  default     = "wordpress-db"
  description = "DB identifier"
}

variable "db_engine" {
  type        = string
  default     = "mysql"
  description = "DB engine"
}

variable "db_engine_version" {
  type        = string
  default     = "5.7"
  description = "DB engine version"
}

variable "db_instance_class" {
  type        = string
  default     = "db.t2.micro"
  description = "DB instance class"
}

variable "db_multi_az" {
  type        = bool
  default     = true
  description = "DB multi-AZ"
}

variable "db_username" {
  type        = string
  default     = "wordpress"
  description = "DB username"
}

variable "db_password" {
  type        = string
  default     = "wordpresspassword"
  description = "DB password"
}

variable "db_name" {
  type        = string
  default     = "wordpress"
  description = "DB name"
}

variable "domain_name" {
  type        = string
  default     = "example.com"
  description = "Domain name"
}

variable "elb_name" {
  type        = string
  default     = "wordpress-elb"
  description = "ELB name"
}

variable "target_group_name" {
  type        = string
  default     = "wordpress-target-group"
  description = "Target group name"
}

variable "asg_name" {
  type        = string
  default     = "wordpress-asg"
  description = "Auto Scaling Group name"
}

variable "asg_max_size" {
  type        = number
  default     = 2
  description = "Auto Scaling Group max size"
}

variable "asg_min_size" {
  type        = number
  default     = 1
  description = "Auto Scaling Group min size"
}

variable "asg_desired_capacity" {
  type        = number
  default     = 1
  description = "Auto Scaling Group desired capacity"
}

variable "launch_config_name" {
  type        = string
  default     = "wordpress-launch-config"
  description = "Launch configuration name"
}

variable "distribution_name" {
  type        = string
  default     = "wordpress-distribution"
  description = "CloudFront distribution name"
}

variable "distribution_comment" {
  type        = string
  default     = "WordPress CloudFront distribution"
  description = "CloudFront distribution comment"
}

variable "certificate_name" {
  type        = string
  default     = "wordpress-certificate"
  description = "ACM certificate name"
}

variable "zone_name" {
  type        = string
  default     = "example.com"
  description = "Route 53 zone name"
}

variable "bucket_name" {
  type        = string
  default     = "wordpress-bucket"
  description = "S3 bucket name"
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Environment"
}

variable "project" {
  type        = string
  default     = "WordPress"
  description = "Project"
}
