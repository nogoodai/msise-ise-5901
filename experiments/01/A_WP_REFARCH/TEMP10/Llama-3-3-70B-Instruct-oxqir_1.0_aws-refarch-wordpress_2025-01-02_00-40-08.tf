provider "aws" {
  region = "us-west-2"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "Availability zones for subnets"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for WordPress EC2 instances"
}

variable "database_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Instance class for RDS instance"
}

variable "elasticache_node_type" {
  type        = string
  default     = "cache.t2.micro"
  description = "Node type for Elasticache cluster"
}

# VPC and networking resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

resource "aws_subnet" "public_subnets" {
  count = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "WordPressPublicSubnet${count.index}"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name = "WordPressPublicRouteTable"
  }
}

resource "aws_route_table_association" "public_route_table_association" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Security groups
resource "aws_security_group" "wp_ec2_sg" {
  name        = "WordPressEC2SG"
  description = "Allow inbound HTTP, HTTPS, and SSH traffic"
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
    Name = "WordPressEC2SG"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "WordPressRDSSG"
  description = "Allow inbound MySQL traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.wp_ec2_sg.id]
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

# EC2 instances for WordPress
resource "aws_instance" "wp_instance" {
  ami           = "ami-0c2ab3b8efb09f272"
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.wp_ec2_sg.id]
  subnet_id = aws_subnet.public_subnets[0].id
  key_name = "wordpress"
  tags = {
    Name = "WordPressInstance"
  }
}

# RDS instance for WordPress database
resource "aws_db_instance" "wp_rds" {
  identifier        = "wordpress-rds"
  instance_class    = var.database_instance_class
  engine            = "mysql"
  engine_version    = "8.0.23"
  db_name           = "wordpressdb"
  username          = "wordpressuser"
  password          = "wordpresspassword"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wp_rds_subnet_group.name
  tags = {
    Name = "WordPressRDS"
  }
}

resource "aws_db_subnet_group" "wp_rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = [for subnet in aws_subnet.public_subnets : subnet.id]
  tags = {
    Name = "WordPressRDSSubnetGroup"
  }
}

# Elastic Load Balancer
resource "aws_alb" "wp_alb" {
  name            = "wordpress-alb"
  internal        = false
  security_groups = [aws_security_group.wp_ec2_sg.id]
  subnets         = [for subnet in aws_subnet.public_subnets : subnet.id]
  tags = {
    Name = "WordPressALB"
  }
}

resource "aws_alb_target_group" "wp_alb_target_group" {
  name     = "wordpress-alb-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressALBTargetGroup"
  }
}

resource "aws_alb_listener" "wp_alb_listener" {
  load_balancer_arn = aws_alb.wp_alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    target_group_arn = aws_alb_target_group.wp_alb_target_group.arn
    type             = "forward"
  }
}

# Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wp_autoscaling_group" {
  name                = "wordpress-autoscaling-group"
  max_size            = 3
  min_size            = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity          = 1
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wp_launch_configuration.name
  vpc_zone_identifier       = [for subnet in aws_subnet.public_subnets : subnet.id]
  tags = {
    Name = "WordPressAutoScalingGroup"
  }
}

resource "aws_launch_configuration" "wp_launch_configuration" {
  name          = "wordpress-launch-configuration"
  image_id      = "ami-0c2ab3b8efb09f272"
  instance_type = var.instance_type
  security_groups = [aws_security_group.wp_ec2_sg.id]
  key_name               = "wordpress"
  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront distribution for content delivery
resource "aws_cloudfront_distribution" "wp_cloudfront_distribution" {
  origin {
    domain_name = aws_alb.wp_alb.dns_name
    origin_id   = "wordpress-alb"
  }
  aliases = ["example.com"]
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-alb"
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
  tags = {
    Name = "WordPressCloudFrontDistribution"
  }
}

# S3 bucket for static assets
resource "aws_s3_bucket" "wp_s3_bucket" {
  bucket = "wordpress-static-assets"
  acl    = "public-read"
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::wordpress-static-assets/*"
    }
  ]
}
POLICY
  tags = {
    Name = "WordPressS3Bucket"
  }
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wp_route53_zone" {
  name = "example.com"
}

resource "aws_route53_record" "wp_route53_record" {
  zone_id = aws_route53_zone.wp_route53_zone.zone_id
  name    = "example.com"
  type    = "A"
  alias {
    name                   = aws_alb.wp_alb.dns_name
    zone_id               = aws_alb.wp_alb.zone_id
    evaluate_target_health = false
  }
}
