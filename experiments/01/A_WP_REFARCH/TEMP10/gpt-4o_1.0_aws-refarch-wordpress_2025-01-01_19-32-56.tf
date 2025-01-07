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
  description = "The AWS region to deploy resources into."
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets."
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "allowed_ssh_ips" {
  description = "List of IPs allowed for SSH access."
  default     = ["0.0.0.0/0"]
}

resource "aws_vpc" "wordpress" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "wordpress-vpc"
  }
}

resource "aws_subnet" "public" {
  for_each = toset(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress.id
  cidr_block        = each.value
  map_public_ip_on_launch = true
  availability_zone = element(data.aws_availability_zones.available.names, index(var.public_subnet_cidrs, each.value))
  tags = {
    Name = "public-subnet-${each.key}"
  }
}

resource "aws_subnet" "private" {
  for_each = toset(var.private_subnet_cidrs)
  vpc_id     = aws_vpc.wordpress.id
  cidr_block = each.value
  availability_zone = element(data.aws_availability_zones.available.names, index(var.private_subnet_cidrs, each.value))
  tags = {
    Name = "private-subnet-${each.key}"
  }
}

resource "aws_internet_gateway" "wordpress" {
  vpc_id = aws_vpc.wordpress.id
  tags = {
    Name = "wordpress-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress.id
  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public
  subnet_id     = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress.id

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
    Name = "web-sg"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "db-sg"
  }
}

resource "aws_instance" "wordpress" {
  ami           = data.aws_ami.latest_amazon_linux.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public[0].id
  security_groups = [aws_security_group.web_sg.name]

  tags = {
    Name = "wordpress-instance"
  }
}

resource "aws_rds_instance" "wordpress_db" {
  allocated_storage    = 20
  instance_class       = "db.t2.small"
  engine               = "mysql"
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password"
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  multi_az             = true
  skip_final_snapshot  = true

  tags = {
    Name = "wordpress-db"
  }
}

resource "aws_elb" "wordpress_lb" {
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
    ssl_certificate_id = data.aws_acm_certificate.main.arn
  }

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  security_groups = [aws_security_group.web_sg.id]

  tags = {
    Name = "wordpress-elb"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = [for subnet in aws_subnet.public : subnet.id]
  launch_configuration = aws_launch_configuration.wordpress.id
}

resource "aws_launch_configuration" "wordpress" {
  image_id        = data.aws_ami.latest_amazon_linux.id
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.web_sg.id]
  user_data       = file("wordpress_userdata.sh")

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_s3_bucket.static_assets.bucket_regional_domain_name
    origin_id   = "wordpress-s3-origin"
  }
  enabled             = true
  is_ipv6_enabled     = true

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "wordpress-s3-origin"
    forwarded_values {
      query_string = false
    }
    viewer_protocol_policy = "redirect-to-https"
  }

  aliases = [aws_route53_record.wordpress.aliases]

  viewer_certificate {
    acm_certificate_arn            = data.aws_acm_certificate.main.arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2018"
  }

  tags = {
    Name = "wordpress-cf"
  }
}

resource "aws_s3_bucket" "static_assets" {
  bucket = "wordpress-static-assets-${random_id.bucket_id.hex}"
  versioning {
    enabled = true
  }

  tags = {
    Name = "wordpress-static-assets"
  }
}

resource "random_id" "bucket_id" {
  byte_length = 4
}

resource "aws_route53_zone" "wordpress" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = "www.example.com"
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_lb.dns_name
    zone_id                = aws_elb.wordpress_lb.zone_id
    evaluate_target_health = true
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

data "aws_availability_zones" "available" {}

data "aws_acm_certificate" "main" {
  domain   = "example.com"
  statuses = ["ISSUED"]
}

output "vpc_id" {
  value = aws_vpc.wordpress.id
}

output "elb_dns" {
  value = aws_elb.wordpress_lb.dns_name
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.wordpress_cf.domain_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.static_assets.bucket
}

output "rds_endpoint" {
  value = aws_rds_instance.wordpress_db.endpoint
}
