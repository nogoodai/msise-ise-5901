# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
}

# Variables
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnets" {
  type = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  type = list(string)
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "wordpress_instance_type" {
  default = "t2.micro"
}

variable "rds_instance_type" {
  default = "db.t2.small"
}

variable "domain_name" {
  default = "example.com"
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

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressPrivateRouteTable"
  }
}

resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnets)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnets[count.index]
  availability_zone = "us-west-2a"
  tags = {
    Name = "WordPressPublicSubnet-${count.index}"
  }
}

resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnets)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = "us-west-2b"
  tags = {
    Name = "WordPressPrivateSubnet-${count.index}"
  }
}

resource "aws_route_table_association" "public_route_table_association" {
  count = length(var.public_subnets)
  subnet_id = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_route_table_association" {
  count = length(var.private_subnets)
  subnet_id = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security groups
resource "aws_security_group" "wordpress_sg" {
  name        = "wordpress_sg"
  description = "WordPress security group"
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
    Name = "WordPressSecurityGroup"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "rds_sg"
  description = "RDS security group"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "RDSSecurityGroup"
  }
}

# EC2 instances for WordPress
resource "aws_instance" "wordpress_instance" {
  ami           = "ami-abc123"
  instance_type = var.wordpress_instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  key_name               = "wordpress_key"
  tags = {
    Name = "WordPressInstance"
  }
}

# RDS instance for WordPress database
resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 10
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = var.rds_instance_type
  name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = "wordpresspassword"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = "wordpress_db_subnet_group"
  tags = {
    Name = "WordPressDBInstance"
  }
}

# Elastic Load Balancer
resource "aws_alb" "wordpress_elb" {
  name            = "wordpress-elb"
  internal        = false
  security_groups = [aws_security_group.wordpress_sg.id]
  subnets         = aws_subnet.public_subnets.*.id
  tags = {
    Name = "WordPressELB"
  }
}

# Target group for WordPress instances
resource "aws_alb_target_group" "wordpress_tg" {
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressTargetGroup"
  }
}

# Listener for HTTP
resource "aws_alb_listener" "wordpress_listener_http" {
  load_balancer_arn = aws_alb.wordpress_elb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    target_group_arn = aws_alb_target_group.wordpress_tg.arn
    type             = "forward"
  }
}

# Listener for HTTPS
resource "aws_alb_listener" "wordpress_listener_https" {
  load_balancer_arn = aws_alb.wordpress_elb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  default_action {
    target_group_arn = aws_alb_target_group.wordpress_tg.arn
    type             = "forward"
  }
}

# Auto Scaling Group for WordPress instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "wordpress-asg"
  launch_configuration = "wordpress-lc"
  min_size            = 1
  max_size            = 2
  vpc_zone_identifier = aws_subnet.public_subnets.*.id
  tags = {
    Name = "WordPressASG"
  }
}

# Launch Configuration for WordPress instances
resource "aws_autoscaling_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = "ami-abc123"
  instance_type = var.wordpress_instance_type
  key_name      = "wordpress_key"
  security_groups = [aws_security_group.wordpress_sg.id]
}

# CloudFront distribution for content delivery
resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = "example.com"
    origin_id   = "S3Origin"
  }
  enabled             = true
  is_ipv6_enabled      = true
  default_root_object = "index.html"
  aliases             = ["example.com"]
  viewer_certificate {
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "sni-only"
  }
}

# S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "example.com"
  acl    = "private"
  tags = {
    Name = "WordPressS3Bucket"
  }
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
  tags = {
    Name = "WordPressRoute53Zone"
  }
}

# A record for ALB
resource "aws_route53_record" "wordpress_a_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "example.com"
  type    = "A"
  alias {
    name                   = aws_alb.wordpress_elb.dns_name
    zone_id               = aws_alb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

# CNAME record for CloudFront
resource "aws_route53_record" "wordpress_cname_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "cdn.example.com"
  type    = "CNAME"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cdn.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cdn.zone_id
    evaluate_target_health = false
  }
}

# Output
output "alb_dns_name" {
  value = aws_alb.wordpress_elb.dns_name
}

output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cdn.domain_name
}

output "rds_instance_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}

output "ec2_instance_id" {
  value = aws_instance.wordpress_instance.id
}
