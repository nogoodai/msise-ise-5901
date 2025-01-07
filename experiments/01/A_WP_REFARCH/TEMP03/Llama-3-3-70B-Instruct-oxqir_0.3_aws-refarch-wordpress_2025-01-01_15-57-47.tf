# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.1.0"
    }
  }
}

# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
}

# Variables for user-configurable values
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "Availability zones for the subnets"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for the EC2 instances"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Instance class for the RDS instance"
}

variable "domain_name" {
  type        = string
  default     = "example.com"
  description = "Domain name for the Route 53 configuration"
}

# VPC and networking resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
  }
}

resource "aws_subnet" "public_subnets" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PublicSubnet${count.index + 1}"
    Environment = "production"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, length(var.availability_zones) + count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PrivateSubnet${count.index + 1}"
    Environment = "production"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = "production"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table_association" "public_subnet_association" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Security groups
resource "aws_security_group" "web_server_sg" {
  name        = "WordPressWebServerSG"
  description = "Security group for the web server"
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
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "WordPressWebServerSG"
    Environment = "production"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "WordPressRDSSG"
  description = "Security group for the RDS instance"
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
    Name        = "WordPressRDSSG"
    Environment = "production"
  }
}

# EC2 instances for WordPress
resource "aws_instance" "wordpress_instance" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  subnet_id = aws_subnet.public_subnets[0].id
  tags = {
    Name        = "WordPressInstance"
    Environment = "production"
  }
}

# RDS instance for the WordPress database
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = var.rds_instance_class
  name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = "wordpresspassword"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  tags = {
    Name        = "WordPressRDS"
    Environment = "production"
  }
}

resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = aws_subnet.private_subnets.*.id
  tags = {
    Name        = "WordPressRDSSubnetGroup"
    Environment = "production"
  }
}

# Elastic Load Balancer
resource "aws_alb" "wordpress_alb" {
  name            = "WordPressALB"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.web_server_sg.id]
  tags = {
    Name        = "WordPressALB"
    Environment = "production"
  }
}

resource "aws_alb_target_group" "wordpress_alb_target_group" {
  name     = "WordPressALBTargetGroup"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressALBTargetGroup"
    Environment = "production"
  }
}

resource "aws_alb_listener" "wordpress_alb_listener" {
  load_balancer_arn = aws_alb.wordpress_alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    target_group_arn = aws_alb_target_group.wordpress_alb_target_group.arn
    type             = "forward"
  }
}

# Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_launch_config.name
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id
  tags = {
    Name        = "WordPressASG"
    Environment = "production"
  }
}

resource "aws_launch_configuration" "wordpress_launch_config" {
  name          = "WordPressLaunchConfig"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_server_sg.id]
  user_data = file("${path.module}/user_data.sh")
  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront distribution for content delivery
resource "aws_cloudfront_distribution" "wordpress_cloudfront" {
  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = "WordPressALB"
  }
  enabled = true
  default_root_object = "index.html"
  aliases = [var.domain_name]
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.wordpress_acm_certificate.arn
    ssl_support_method  = "sni-only"
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  tags = {
    Name        = "WordPressCloudFront"
    Environment = "production"
  }
}

resource "aws_acm_certificate" "wordpress_acm_certificate" {
  domain_name       = var.domain_name
  validation_method = "DNS"
  tags = {
    Name        = "WordPressACMCertificate"
    Environment = "production"
  }
}

# S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = var.domain_name
  acl    = "private"
  tags = {
    Name        = "WordPressS3Bucket"
    Environment = "production"
  }
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_route53_zone" {
  name = var.domain_name
  tags = {
    Name        = "WordPressRoute53Zone"
    Environment = "production"
  }
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cloudfront.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cloudfront.zone_id
    evaluate_target_health = false
  }
}

# Outputs
output "alb_dns_name" {
  value = aws_alb.wordpress_alb.dns_name
}

output "rds_instance_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cloudfront.domain_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3_bucket.id
}

output "route53_zone_id" {
  value = aws_route53_zone.wordpress_route53_zone.id
}
