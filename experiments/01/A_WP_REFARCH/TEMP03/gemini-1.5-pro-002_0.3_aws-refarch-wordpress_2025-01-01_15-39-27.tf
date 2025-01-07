terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "project_name" {
  type    = string
  default = "wordpress-project"
}

variable "environment" {
  type    = string
  default = "production"
}


# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project_name}-public-subnet-1"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "public_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  tags = {
    Name        = "${var.project_name}-public-subnet-2"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name        = "${var.project_name}-public-route-table"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

data "aws_availability_zones" "available" {}

# Security Groups
resource "aws_security_group" "web_sg" {
 name        = "${var.project_name}-web-sg"
  description = "Allow inbound HTTP, HTTPS and SSH"
  vpc_id      = aws_vpc.main.id

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
    cidr_blocks = ["0.0.0.0/0"] # Replace with your IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-web-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}


# EC2 Instances and Auto Scaling
resource "aws_launch_template" "wordpress_lt" {
  name_prefix = "${var.project_name}-wordpress-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  network_interfaces {
    security_groups = [aws_security_group.web_sg.id]
    associate_public_ip_address = true
    subnet_id                   = aws_subnet.public_1.id
  }

 lifecycle {
    create_before_destroy = true
  }
}

data "aws_ami" "amazon_linux" {
 most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-5.10-hvm-*-x86_64-gp2"]
  }
}


resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "${var.project_name}-wordpress-asg"
  launch_template {
    id      = aws_launch_template.wordpress_lt.id
    version = "$latest"
  }
 min_size                  = 1
  max_size                  = 2
  vpc_zone_identifier = [aws_subnet.public_1.id, aws_subnet.public_2.id]


}


# RDS Instance
resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-db-subnet-group"
 subnet_ids = [aws_subnet.public_1.id, aws_subnet.public_2.id] # Ideally, use private subnets for RDS
}


resource "aws_db_instance" "default" {
  identifier             = "${var.project_name}-db"
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_subnet_group_name   = aws_db_subnet_group.default.name
  username               = "admin" # Replace with your username
  password               = "password123" # Replace with a strong password
  skip_final_snapshot    = true
 publicly_accessible    = false # Ideally, keep this false and access via bastion
  vpc_security_group_ids = [aws_security_group.web_sg.id] # Ideally, create a separate security group for RDS

}



# S3 Bucket
resource "aws_s3_bucket" "static_assets" {
  bucket = "${var.project_name}-static-assets"
  acl    = "private"

}


# Load Balancer
resource "aws_lb" "wordpress_lb" {
 name               = "${var.project_name}-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
 subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]

}

resource "aws_lb_target_group" "wordpress_tg" {
  name        = "${var.project_name}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

 health_check {
    path     = "/"
    port     = "80"
    protocol = "HTTP"
  }
}


resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}



# CloudFront Distribution (Basic setup - needs more configuration for production)
resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_lb.wordpress_lb.dns_name
    origin_id   = "${var.project_name}-lb-origin"

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "http-only" # Or match-viewer
      origin_ssl_protocols = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"


  viewer_certificate {
    cloudfront_default_certificate = true
  }


  default_cache_behavior {
    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]
    target_origin_id = "${var.project_name}-lb-origin"
    viewer_protocol_policy = "redirect-to-https" # or allow-all, https-only
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

 min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }


  price_class = "PriceClass_All"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}



# Route53 (Example - replace with your domain)
resource "aws_route53_zone" "example_com" {
  name = "example.com." # Replace with your domain
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.example_com.zone_id
  name    = "www.example.com." # Replace with your subdomain
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cdn.hosted_zone_id
    evaluate_target_health = false
  }
}


output "cloudfront_domain" {
  value = aws_cloudfront_distribution.wordpress_cdn.domain_name
}

output "lb_dns_name" {
  value = aws_lb.wordpress_lb.dns_name
}

output "rds_endpoint" {
  value = aws_db_instance.default.endpoint
}


