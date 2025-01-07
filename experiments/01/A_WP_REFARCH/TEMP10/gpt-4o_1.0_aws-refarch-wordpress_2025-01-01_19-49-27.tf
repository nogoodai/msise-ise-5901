terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-1"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidr" {
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "instance_type" {
  default = "t2.micro"
}

variable "db_instance_class" {
  default = "db.t2.small"
}

variable "db_subnet_ids" {
  default = ["subnet-xxxxxx", "subnet-xxxxxx"]
}

variable "acm_domain_name" {
  description = "Domain name for ACM SSL certificate"
  default     = "example.com"
}

variable "route53_zone_id" {
  description = "Route53 Hosted Zone ID"
  default     = "Z1XXXXXXX"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_internet_gateway" "public_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

resource "aws_subnet" "public_subnet" {
  count                   = length(var.public_subnet_cidr)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = element(var.public_subnet_cidr, count.index)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name = "PublicSubnet-${count.index}"
  }
}

resource "aws_subnet" "private_subnet" {
  count             = length(var.private_subnet_cidr)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = element(var.private_subnet_cidr, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "PrivateSubnet-${count.index}"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.public_igw.id
  }
  tags = {
    Name = "PublicRT"
  }
}

resource "aws_route_table_association" "public_rt_assoc" {
  count          = length(aws_subnet.public_subnet)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
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
    cidr_blocks = ["203.0.113.0/24"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "WebServerSG"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
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
    Name = "DatabaseSG"
  }
}

resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  instance_class       = var.db_instance_class
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password"
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.name
  multi_az             = true
  tags = {
    Name = "WordPressDB"
  }
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = var.db_subnet_ids
  tags = {
    Name = "DBSubnetGroup"
  }
}

resource "aws_launch_configuration" "wordpress_launch_config" {
  name          = "WordPressLaunchConfig"
  image_id      = "ami-12345678"
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_sg.id]
  user_data = <<-EOF
              #!/bin/bash
              # Install WordPress 
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              # Placeholder for web server setup, like installing PHP, WordPress, etc.
              EOF
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  vpc_zone_identifier  = aws_subnet.private_subnet[*].id
  launch_configuration = aws_launch_configuration.wordpress_launch_config.name
  min_size             = 2
  max_size             = 5
  desired_capacity     = 3
  tags = [{
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }]
}

resource "aws_elb" "wordpress_alb" {
  name               = "WordPressALB"
  availability_zones = data.aws_availability_zones.available.names
  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }
  listener {
    instance_port     = 443
    instance_protocol = "HTTPS"
    lb_port           = 443
    lb_protocol       = "HTTPS"
    ssl_certificate_id = aws_acm_certificate.domain_cert.arn
  }
  instances = aws_autoscaling_group.wordpress_asg.instances[*]
  security_groups = [
    aws_security_group.web_sg.id
  ]
  tags = {
    Name = "WordPressALB"
  }
}

resource "aws_acm_certificate" "domain_cert" {
  domain_name = var.acm_domain_name
  validation_method = "DNS"
}

resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_elb.wordpress_alb.dns_name
    origin_id   = "wordpress-alb-origin"
  }
  enabled             = true
  default_cache_behavior {
    target_origin_id = "wordpress-alb-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.domain_cert.arn
    ssl_support_method = "sni-only"
  }
}

resource "aws_s3_bucket" "wp_assets" {
  bucket = "wordpress-static-assets-${random_id.bucket_id.hex}"
  acl    = "public-read"
  tags = {
    Name = "WordPressAssets"
  }
}

resource "aws_s3_bucket_public_access_block" "wp_assets_block" {
  bucket = aws_s3_bucket.wp_assets.id
  block_public_acls   = true
  block_public_policy = true
  ignore_public_acls  = true
  restrict_public_buckets = true
}

resource "aws_route53_record" "www" {
  zone_id = var.route53_zone_id
  name    = "www.${var.acm_domain_name}"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cf.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cf.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "random_id" "bucket_id" {
  byte_length = 8
}

output "alb_dns_name" {
  value = aws_elb.wordpress_alb.dns_name
}

output "cloudfront_url" {
  value = aws_cloudfront_distribution.wordpress_cf.domain_name
}

output "db_instance_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}
