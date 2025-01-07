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
  description = "The AWS region to create resources in."
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "The CIDR block for the public subnet."
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "The CIDR block for the private subnet."
  default     = "10.0.2.0/24"
}

variable "ssh_ingress_cidr" {
  description = "The CIDR block allowed to SSH into the bastion and web servers."
  default     = "0.0.0.0/0"
}

variable "s3_bucket_name" {
  description = "The name of the S3 bucket for static assets."
  default     = "wordpress-static-assets"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr

  tags = {
    Name        = "wordpress-vpc"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name        = "wordpress-public-subnet"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = "${var.aws_region}a"

  tags = {
    Name        = "wordpress-private-subnet"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "wordpress-igw"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name        = "wordpress-public-rt"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_server_sg" {
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
    cidr_blocks = [var.ssh_ingress_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "wordpress-web-sg"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-launch-configuration"
  image_id      = "ami-12345678" # Use actual AMI ID
  instance_type = "t2.micro"
  security_groups = [aws_security_group.web_server_sg.id]
  user_data = <<-EOF
              #!/bin/bash
              yum install -y httpd php php-mysqlnd
              systemctl enable httpd
              systemctl start httpd
              # Additional WordPress setup here
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  availability_zones   = ["${var.aws_region}a"]
  desired_capacity     = 1
  max_size             = 3
  min_size             = 1
  launch_configuration = aws_launch_configuration.wordpress_lc.id
  vpc_zone_identifier  = [aws_subnet.public.id]

  tags = [{
    key                 = "Name"
    value               = "wordpress-instance"
    propagate_at_launch = true
  }]
}

resource "aws_elb" "wordpress_elb" {
  name = "wordpress-elb"

  availability_zones = ["${var.aws_region}a"]
  
  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }
  
  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  instances            = [aws_autoscaling_group.wordpress_asg.id]
  cross_zone_load_balancing = true
  
  security_groups = [aws_security_group.web_server_sg.id]

  tags = {
    Name        = "wordpress-elb"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_s3_bucket" "static_assets" {
  bucket = var.s3_bucket_name

  tags = {
    Name        = "wordpress-static-assets"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpressELB"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
    }
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpressELB"

    forwarded_values {
      query_string = false

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "allow-all"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name        = "wordpress-cf-distribution"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_db_instance" "wordpress_db" {
  identifier         = "wordpress-db"
  engine             = "mysql"
  instance_class     = "db.t2.micro"
  allocated_storage  = 20
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.id
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  username           = "admin"
  password           = "password" # Use a secure method to pass passwords
  skip_final_snapshot = true

  tags = {
    Name        = "wordpress-database"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = [aws_subnet.private.id]

  tags = {
    Name        = "wordpress-db-subnet-group"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com" # Use actual domain name

  tags = {
    Name        = "wordpress-zone"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route53_record" "wordpress_alb_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "www.example.com" # Use actual subdomain or domain name
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id                = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = true
  }
}

output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "load_balancer_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.static_assets.bucket
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_distribution.domain_name
}

output "db_instance_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}
