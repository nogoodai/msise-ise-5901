# Configure the AWS provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Configure provider
provider "aws" {
  region = "us-west-2"
}

# Define VPC variables
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "aws_region" {
  default = "us-west-2"
}

variable "availability_zones" {
  default = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

# Create VPC
resource "aws_vpc" "word_press_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  enable_classiclink   = false
  instance_tenancy     = "default"
  tags = {
    Name = "WordPressVPC"
  }
}

# Create public subnets
resource "aws_subnet" "public_subnet" {
  count             = length(var.availability_zones)
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  vpc_id            = aws_vpc.word_press_vpc.id
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "PublicSubnet-${count.index+1}"
  }
}

# Create private subnets
resource "aws_subnet" "private_subnet" {
  count             = length(var.availability_zones)
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + length(var.availability_zones))
  vpc_id            = aws_vpc.word_press_vpc.id
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PrivateSubnet-${count.index+1}"
  }
}

# Create internet gateway
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.word_press_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Create route table for public subnets
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.word_press_vpc.id
  tags = {
    Name = "WordPressPublicRouteTable"
  }
}

# Create route for internet gateway
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public_subnet_association" {
  count          = length(var.availability_zones)
  route_table_id = aws_route_table.public_route_table.id
  subnet_id      = aws_subnet.public_subnet[count.index].id
}

# Create route table for private subnets
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.word_press_vpc.id
  tags = {
    Name = "WordPressPrivateRouteTable"
  }
}

# Create NAT gateway for private subnets
resource "aws_nat_gateway" "nat_gateway" {
  count         = length(var.availability_zones)
  allocation_id = aws_eip.nat_gateway_eip[count.index].id
  subnet_id     = aws_subnet.public_subnet[count.index].id
}

# Create elastic IP for NAT gateway
resource "aws_eip" "nat_gateway_eip" {
  count      = length(var.availability_zones)
  vpc        = true
  depends_on = [aws_internet_gateway.internet_gateway]
}

# Create route for NAT gateway
resource "aws_route" "private_route" {
  count                  = length(var.availability_zones)
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway[count.index].id
}

# Associate private subnets with private route table
resource "aws_route_table_association" "private_subnet_association" {
  count          = length(var.availability_zones)
  route_table_id = aws_route_table.private_route_table.id
  subnet_id      = aws_subnet.private_subnet[count.index].id
}

# Define web server security group variables
variable "ssh_source_ip" {
  default = "0.0.0.0/0"
}

variable "http_source_ip" {
  default = "0.0.0.0/0"
}

variable "https_source_ip" {
  default = "0.0.0.0/0"
}

# Create security group for web server
resource "aws_security_group" "web_server_sg" {
  name        = "WordPressWebServerSG"
  description = "Security group for web server"
  vpc_id      = aws_vpc.word_press_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_source_ip]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.http_source_ip]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.https_source_ip]
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

# Create RDS security group
resource "aws_security_group" "rds_sg" {
  name        = "WordPressRDSSG"
  description = "Security group for RDS"
  vpc_id      = aws_vpc.word_press_vpc.id
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
    Name = "WordPressRDSSG"
  }
}

# Create EC2 instance for WordPress
resource "aws_instance" "web_server" {
  ami           = "ami-0892d3c7ee96c0bf7"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  subnet_id = aws_subnet.public_subnet[0].id
  key_name               = "wordpress-Key"
  user_data              = file("${path.module}/wordpress.sh")
  tags = {
    Name = "WordPressWebServer"
  }
}

# Create RDS instance for WordPress
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 10
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = "db.t2.micro"
  db_name              = "wordpressdb"
  username             = "wordpressuser"
  password             = "wordpresspassword"
  parameter_group_name = "default.mysql8.0"
  db_subnet_group_name = aws_db_subnet_group.wordpress_subnets.id
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot  = true
}

# Create DB subnet group
resource "aws_db_subnet_group" "wordpress_subnets" {
  name       = "WordPressSubnets"
  subnet_ids = [aws_subnet.private_subnet[0].id, aws_subnet.private_subnet[1].id]
}

# Create Elastic Load Balancer
resource "aws_alb" "wordpress_alb" {
  name            = "WordPressALB"
  subnets         = aws_subnet.public_subnet[*].id
  security_groups = [aws_security_group.web_server_sg.id]
}

# Create target group for WordPress
resource "aws_alb_target_group" "wordpress_tg" {
  name     = "WordPressTG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.word_press_vpc.id
}

# Create listener for WordPress
resource "aws_alb_listener" "wordpress_listener" {
  load_balancer_arn = aws_alb.wordpress_alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    target_group_arn = aws_alb_target_group.wordpress_tg.arn
    type             = "forward"
  }
}

# Create auto scaling group for WordPress
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  max_size                  = 3
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity         = 1
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = aws_subnet.public_subnet[*].id
}

# Create launch configuration for WordPress
resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = "ami-0892d3c7ee96c0bf7"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.web_server_sg.id]
  key_name               = "wordpress-Key"
  user_data              = file("${path.module}/wordpress.sh")
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cdf" {
  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = "wordpress-origin"
  }
  enabled             = true
  default_root_object = "index.html"
  aliases             = ["example.com"]
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-origin"
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
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "sni-only"
  }
}

# Create S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_s3" {
  bucket = "wordpress-static-assets"
  acl    = "public-read"
}

# Create Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
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

# Output critical information
output "alb_dns_name" {
  value = aws_alb.wordpress_alb.dns_name
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3.id
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.wordpress_cdf.id
}

output "route53_zone_id" {
  value = aws_route53_zone.wordpress_zone.zone_id
}
