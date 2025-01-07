terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy resources in."
  default     = "us-east-1"
}

variable "allowed_ssh_ips" {
  description = "List of IPs allowed to SSH into instances."
  type        = list(string)
  default     = ["0.0.0.0/0"] # Adjust as per need
}

variable "environment" {
  description = "Environment tag for resources."
  default     = "production"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets."
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "db_instance_class" {
  description = "RDS instance class."
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Database name for WordPress."
  default     = "wordpressdb"
}

variable "db_username" {
  description = "Username for the RDS database."
  default     = "admin"
}

variable "db_password" {
  description = "Password for the RDS database."
  default     = "password" # Replace with secure generation in production
}

variable "key_name" {
  description = "SSH key pair name for EC2 access."
  default     = "my-key-pair"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "wordpress-igw"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name        = "wordpress-public-subnet-${count.index}"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name        = "wordpress-private-subnet-${count.index}"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "wordpress-public-rt"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_route" "igw_route" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

# Security Groups
resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.main.id

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
    cidr_blocks = var.allowed_ssh_ips
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "wordpress-web-sg"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "wordpress-db-sg"
    Environment = var.environment
    Project     = "WordPress"
  }
}

# EC2 Instances and ASG
resource "aws_autoscaling_group" "web_asg" {
  availability_zones = data.aws_availability_zones.available.names
  launch_configuration = aws_launch_configuration.web_launch_config.name
  min_size = 1
  max_size = 3

  tags = [{
    key                 = "Name"
    value               = "wordpress-asg-instance"
    propagate_at_launch = true
  }, {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }, {
    key                 = "Project"
    value               = "WordPress"
    propagate_at_launch = true
  }]
}

resource "aws_launch_configuration" "web_launch_config" {
  image_id                   = data.aws_ami.latest_amazon_linux.id
  instance_type              = "t3.micro"
  security_groups            = [aws_security_group.web_sg.id]
  key_name                   = var.key_name
  associate_public_ip_address = true
  user_data                  = file("user_data.sh")

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_ami" "latest_amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# RDS Instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = var.db_instance_class
  name                 = var.db_name
  username             = var.db_username
  password             = var.db_password
  skip_final_snapshot  = true
  db_subnet_group_name = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  multi_az             = true

  tags = {
    Name        = "wordpress-rds-instance"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_db_subnet_group" "default" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "wordpress-db-subnet-group"
    Environment = var.environment
    Project     = "WordPress"
  }
}

# Elastic Load Balancer (ALB)
resource "aws_lb" "public_alb" {
  name               = "wordpress-public-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name        = "wordpress-public-alb"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.public_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

resource "aws_lb_target_group" "wordpress_tg" {
  name     = "wordpress-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "wordpress-tg"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_lb_target_group_attachment" "asg" {
  target_group_arn = aws_lb_target_group.wordpress_tg.arn
  target_id        = aws_autoscaling_group.web_asg.id
  port             = 80
}

# CloudFront
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_lb.public_alb.dns_name
    origin_id   = "ALBWordPress"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for WordPress application"
  
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ALBWordPress"
    
    forwarded_values {
      query_string = false
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
    Name        = "wordpress-cloudfront"
    Environment = var.environment
    Project     = "WordPress"
  }
}

# S3 Bucket for static assets
resource "aws_s3_bucket" "wordpress_assets" {
  bucket_prefix = "wordpress-static-assets-"

  tags = {
    Name        = "wordpress-static-assets"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket_public_access_block" "block" {
  bucket = aws_s3_bucket.wordpress_assets.id

  block_public_acls   = true
  block_public_policy = true
  ignore_public_acls  = true
  restrict_public_buckets = true
}

# Route 53
resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = {
    Name        = "wordpress-r53-zone"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www"
  type    = "A"

  alias {
    name                   = aws_lb.public_alb.dns_name
    zone_id                = aws_lb.public_alb.zone_id
    evaluate_target_health = true
  }
}

# Outputs
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_alb_dns" {
  value = aws_lb.public_alb.dns_name
}

output "db_instance_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "cloudfront_distribution_domain" {
  value = aws_cloudfront_distribution.wordpress_distribution.domain_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_assets.id
}
