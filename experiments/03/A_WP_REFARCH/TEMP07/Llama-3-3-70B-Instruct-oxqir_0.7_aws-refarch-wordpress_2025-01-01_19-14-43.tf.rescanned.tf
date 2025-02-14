# Required provider configuration
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Configure the AWS provider
provider "aws" {
  region = "us-west-2"
}

# VPC configuration
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name        = "WordPressVPC"
    Environment = "prod"
    Project     = "WordPress"
  }
}

# Subnet configuration
variable "public_subnet_cidr_blocks" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "CIDR blocks for the public subnets"
}

variable "private_subnet_cidr_blocks" {
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
  description = "CIDR blocks for the private subnets"
}

resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidr_blocks)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidr_blocks[count.index]
  availability_zone = "us-west-2a"
  map_public_ip_on_launch = false
  tags = {
    Name        = "PublicSubnet${count.index + 1}"
    Environment = "prod"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidr_blocks)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidr_blocks[count.index]
  availability_zone = "us-west-2b"
  tags = {
    Name        = "PrivateSubnet${count.index + 1}"
    Environment = "prod"
    Project     = "WordPress"
  }
}

# Internet gateway configuration
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "prod"
    Project     = "WordPress"
  }
}

# Route table configuration
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = "prod"
    Project     = "WordPress"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table_association" "public_subnet_association" {
  count          = length(var.public_subnet_cidr_blocks)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Security group configuration
resource "aws_security_group" "web_server_sg" {
  name        = "WordPressWebServerSG"
  description = "Security group for WordPress web servers"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow HTTP traffic from within the VPC"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow HTTPS traffic from within the VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "WordPressWebServerSG"
    Environment = "prod"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "db_sg" {
  name        = "WordPressDBSG"
  description = "Security group for WordPress database"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
    description     = "Allow MySQL traffic from web servers"
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.web_server_sg.id]
    description     = "Allow all outbound traffic to web servers"
  }

  tags = {
    Name        = "WordPressDBSG"
    Environment = "prod"
    Project     = "WordPress"
  }
}

# EC2 instance configuration
variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for WordPress instances"
}

resource "aws_instance" "wordpress_instances" {
  count         = 2
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.web_server_sg.id
  ]
  subnet_id = aws_subnet.public_subnets[count.index].id
  key_name  = "wordpress-key"
  associate_public_ip_address = false
  monitoring = true
  ebs_optimized = true

  tags = {
    Name        = "WordPressInstance${count.index + 1}"
    Environment = "prod"
    Project     = "WordPress"
  }
}

# RDS instance configuration
variable "db_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Instance class for RDS instance"
}

resource "aws_db_instance" "wordpress_db" {
  instance_class = var.db_instance_class
  engine         = "mysql"
  engine_version = "8.0.23"
  publicly_accessible = false
  vpc_security_group_ids = [
    aws_security_group.db_sg.id
  ]
  allocated_storage    = 20
  storage_type         = "gp2"
  parameter_group_name = "default.mysql8.0"
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  skip_final_snapshot  = true
  backup_retention_period = 12
  storage_encrypted = true
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]
  iam_database_authentication_enabled = true

  tags = {
    Name        = "WordPressDB"
    Environment = "prod"
    Project     = "WordPress"
  }
}

# DB subnet group configuration
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnets[0].id, aws_subnet.private_subnets[1].id]

  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = "prod"
    Project     = "WordPress"
  }
}

# Elastic Load Balancer configuration
resource "aws_alb" "wordpress_alb" {
  name            = "WordPressALB"
  subnets         = [aws_subnet.public_subnets[0].id, aws_subnet.public_subnets[1].id]
  security_groups = [aws_security_group.web_server_sg.id]
  enable_deletion_protection = true
  drop_invalid_header_fields = true

  tags = {
    Name        = "WordPressALB"
    Environment = "prod"
    Project     = "WordPress"
  }
}

# Target group configuration
resource "aws_alb_target_group" "wordpress_target_group" {
  name     = "WordPressTargetGroup"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    interval            = 30
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

# Auto Scaling Group configuration
resource "aws_autoscaling_group" "wordpress_autoscaling_group" {
  name                      = "WordPressASG"
  max_size                  = 5
  min_size                  = 2
  desired_capacity          = 2
  launch_configuration      = aws_launch_configuration.wordpress_launch_config.name
  vpc_zone_identifier       = [aws_subnet.public_subnets[0].id, aws_subnet.public_subnets[1].id]
  target_group_arns         = [aws_alb_target_group.wordpress_target_group.arn]

  tags = [
    {
      key                 = "Name"
      value               = "WordPressASG"
      propagate_at_launch = true
    }
  ]
}

# Launch configuration
resource "aws_launch_configuration" "wordpress_launch_config" {
  name          = "WordPressLaunchConfig"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.web_server_sg.id
  ]
  key_name               = "wordpress-key"
  user_data              = file("${path.module}/user_data.sh")
  lifecycle {
    create_before_destroy = true
  }

  enable_monitoring = true
  ebs_optimized = true
}

# CloudFront distribution configuration
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = "WordPressOrigin"
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WordPressOrigin"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "https-only"
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
    acm_certificate_arn = aws_acm_certificate.wordpress_certificate.arn
  }

  logging_config {
    bucket = aws_s3_bucket.wordpress_bucket.id
    prefix = "/wordpress"
  }
}

resource "aws_acm_certificate" "wordpress_certificate" {
  domain_name       = "example.com"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "wordpress_validation" {
  certificate_arn = aws_acm_certificate.wordpress_certificate.arn
  validation_record {
    name    = aws_route53_record.wordpress_validation.name
    value   = aws_acm_certificate.wordpress_certificate.domain_validation_options[0].resource_record_value
    type    = aws_acm_certificate.wordpress_certificate.domain_validation_options[0].resource_record_type
  }
}

resource "aws_route53_record" "wordpress_validation" {
  name    = aws_acm_certificate.wordpress_certificate.domain_validation_options[0].resource_record_name
  type    = aws_acm_certificate.wordpress_certificate.domain_validation_options[0].resource_record_type
  zone_id = aws_route53_zone.wordpress_zone.id
  records = [aws_acm_certificate.wordpress_certificate.domain_validation_options[0].resource_record_value]
  ttl     = 60
}

# S3 bucket configuration
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-bucket"
  acl    = "private"

  versioning {
    enabled = true
  }

  logging {
    target_bucket = aws_s3_bucket.wordpress_bucket.id
    target_prefix  = "/logs/"
  }

  tags = {
    Name        = "WordPressBucket"
    Environment = "prod"
    Project     = "WordPress"
  }
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"

  tags = {
    Name        = "WordPressZone"
    Environment = "prod"
    Project     = "WordPress"
  }
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_alb.wordpress_alb.dns_name
    zone_id                = aws_alb.wordpress_alb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_query_log" "wordpress_log" {
  cloudwatch_log_group_arn = aws_cloudwatch_log_group.wordpress_log_group.arn
  zone_id                  = aws_route53_zone.wordpress_zone.id
}

resource "aws_cloudwatch_log_group" "wordpress_log_group" {
  name = "wordpress-log-group"

  tags = {
    Name        = "WordPressLogGroup"
    Environment = "prod"
    Project     = "WordPress"
  }
}

# Output values
output "alb_dns_name" {
  value       = aws_alb.wordpress_alb.dns_name
  description = "The DNS name of the ALB"
}

output "rds_endpoint" {
  value       = aws_db_instance.wordpress_db.endpoint
  description = "The endpoint of the RDS instance"
}

output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.wordpress_distribution.id
  description = "The ID of the CloudFront distribution"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.wordpress_bucket.id
  description = "The name of the S3 bucket"
}

output "route53_zone_id" {
  value       = aws_route53_zone.wordpress_zone.zone_id
  description = "The ID of the Route 53 zone"
}
