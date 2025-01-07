# Provider configuration for AWS
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.1.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

# Variables for reusable values
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for VPC"
}

variable "public_subnet_cidr_blocks" {
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
  description = "CIDR blocks for public subnets"
}

variable "private_subnet_cidr_blocks" {
  type        = list(string)
  default     = ["10.0.2.0/24", "10.0.3.0/24"]
  description = "CIDR blocks for private subnets"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c55b159cbfafe1f0"
  description = "AMI ID for EC2 instances"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for EC2 instances"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Instance class for RDS instance"
}

variable "database_username" {
  type        = string
  default     = "wordpressuser"
  description = "Username for RDS database"
}

variable "database_password" {
  type        = string
  sensitive   = true
  description = "Password for RDS database"
}

# VPC and networking resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_subnet" "public_subnets" {
  count = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidr_blocks[count.index]
  availability_zone = "us-west-2${count.index + 1}"
  tags = {
    Name = "PublicSubnet${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidr_blocks[count.index]
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

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table_association" "public_route_table_associations" {
  count = 2
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

resource "aws_route_table_association" "private_route_table_associations" {
  count = 2
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security groups
resource "aws_security_group" "wordpress_sg" {
  name        = "WordPressSG"
  description = "Security group for WordPress instances"
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
    cidr_blocks = ["<your_IP>'/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WordPressSG"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "RDSSG"
  description = "Security group for RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
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

# EC2 instances
resource "aws_instance" "wordpress_instances" {
  count = 2
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public_subnets[count.index].id
  vpc_security_group_ids = [
    aws_security_group.wordpress_sg.id
  ]

  tags = {
    Name = "WordPressInstance${count.index + 1}"
  }
}

# RDS instance
resource "aws_db_instance" "wordpress_rds" {
  instance_class = var.rds_instance_class
  engine          = "mysql"
  username        = var.database_username
  password        = var.database_password
  availability_zone = "us-west-2a"
  vpc_security_group_ids = [
    aws_security_group.rds_sg.id
  ]

  tags = {
    Name = "WordPressRDS"
  }
}

# Elastic Load Balancer
resource "aws_alb" "wordpress_alb" {
  name            = "WordPressALB"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_sg.id]

  tags = {
    Name = "WordPressALB"
  }
}

resource "aws_alb_target_group" "wordpress_target_group" {
  name     = "WordPressTargetGroup"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  tags = {
    Name = "WordPressTargetGroup"
  }
}

resource "aws_alb_listener" "wordpress_listener" {
  load_balancer_arn = aws_alb.wordpress_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.wordpress_target_group.arn
    type             = "forward"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "WordPressASG"
  max_size            = 5
  min_size            = 2
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete         = true
  launch_configuration = aws_launch_configuration.wordpress_launch_config.name
  vpc_zone_identifier = aws_subnet.public_subnets.*.id

  tags = [
    {
      key                 = "Name"
      value               = "WordPressInstance"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_launch_config" {
  name          = "WordPressLaunchConfig"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.wordpress_sg.id
  ]

  user_data = file("./wordpress_user_data.sh")

  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cloudfront" {
  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = "WordPressALB"
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
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
    cloudfront_default_certificate = true
  }
}

# S3 bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-bucket"
  acl    = "public-read"

  tags = {
    Name = "WordPressBucket"
  }
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_dns_zone" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress_dns_record" {
  zone_id = aws_route53_zone.wordpress_dns_zone.id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_alb.wordpress_alb.dns_name
    zone_id               = aws_alb.wordpress_alb.zone_id
    evaluate_target_health = false
  }
}

output "wordpress_alb_dns_name" {
  value = aws_alb.wordpress_alb.dns_name
}

output "wordpress_rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "wordpress_cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cloudfront.domain_name
}
