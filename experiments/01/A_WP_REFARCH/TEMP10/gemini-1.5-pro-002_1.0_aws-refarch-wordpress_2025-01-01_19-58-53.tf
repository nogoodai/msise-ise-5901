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
  default = "dev"
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
resource "aws_security_group" "web_server_sg" {
 name = "${var.project_name}-web-server-sg"
  description = "Allow HTTP, HTTPS and SSH inbound traffic"
  vpc_id = aws_vpc.main.id

 ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
 from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Restrict in production
  }


  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-web-sg"
  }
}



# EC2 Instances & Autoscaling

resource "aws_launch_template" "wordpress_lt" {


  name_prefix = "${var.project_name}-wordpress-lt-"


  image_id = "ami-0c02fb559e5b06e6c" # Replace with desired AMI
  instance_type = "t2.micro"


    network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web_server_sg.id]



  }

  user_data = filebase64("./user_data.sh") # WordPress install script



 lifecycle {
    create_before_destroy = true
  }


}



# User Data for Wordpress installation (user_data.sh)
# #!/bin/bash
# sudo yum update -y
# sudo yum install httpd php mysql php-mysql -y
# sudo systemctl start httpd
# sudo systemctl enable httpd
# echo "<?php phpinfo(); ?>" > /var/www/html/index.php



resource "aws_autoscaling_group" "wordpress_asg" {



  name_prefix = "${var.project_name}-wordpress-asg-"

  min_size = 1
  max_size = 3
  desired_capacity = 2

  vpc_zone_identifier = [aws_subnet.public_1.id, aws_subnet.public_2.id]

 launch_template {
    id      = aws_launch_template.wordpress_lt.id
    version = "$Latest"

  }


 health_check_type = "ELB"


  target_group_arns = [aws_lb_target_group.wordpress_tg.arn]
 tag {
    key                 = "Name"
    value              = "${var.project_name}-wordpress-instance"
    propagate_at_launch = true
  }



}


resource "aws_lb" "wordpress_lb" {


 name_prefix = "${var.project_name}-alb-"



  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_server_sg.id]
 subnets = [aws_subnet.public_1.id, aws_subnet.public_2.id]





  tags = {
    Name = "${var.project_name}-alb"
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

resource "aws_lb_target_group" "wordpress_tg" {


 name_prefix = "${var.project_name}-wordpress-tg-"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id



 health_check {
    path                = "/"
  }





}



# RDS Instance
resource "aws_db_instance" "wordpress_db" {
  identifier_prefix = "${var.project_name}-db-"


  allocated_storage      = 20
  storage_type           = "gp2"
  engine                = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t2.micro"
  username              = "admin"  # Replace with secure credentials
  password              = "password" # Replace with secure credentials
  skip_final_snapshot = true


  db_subnet_group_name = aws_db_subnet_group.default.name



  vpc_security_group_ids      = [aws_security_group.web_server_sg.id]
}


resource "aws_db_subnet_group" "default" {
 name       = "${var.project_name}-db-subnet-group"

  subnet_ids = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}


# S3 Bucket
resource "aws_s3_bucket" "wordpress_assets" {

  bucket = "${var.project_name}-assets"
  acl    = "private"



}



# Cloudfront Distribution (Basic)
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name

    origin_id = aws_s3_bucket.wordpress_assets.id



 custom_origin_config {
      http_port              = "80"
      https_port             = "443"
      origin_protocol_policy = "http-only" # Or match-viewer
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }


 enabled             = true
  is_ipv6_enabled     = true


  default_cache_behavior {




    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.wordpress_assets.id
    viewer_protocol_policy = "redirect-to-https"
  }


 price_class = "PriceClass_100"
  restrictions {
 geo_restriction {
      restriction_type = "none"

    }
  }


  viewer_certificate {
    cloudfront_default_certificate = true


  }

}



# Route53 (example.com) - Adapt as needed
resource "aws_route53_zone" "example_com" {
  name = "example.com." # Replace with your domain


}

resource "aws_route53_record" "www" {


  zone_id = aws_route53_zone.example_com.zone_id
 name    = "www" # Set your subdomain

 type    = "A"



  alias {
    name                   = aws_lb.wordpress_lb.dns_name
    zone_id                = aws_lb.wordpress_lb.zone_id
    evaluate_target_health = true

  }
}


output "load_balancer_url" {

  value = aws_lb.wordpress_lb.dns_name
}

output "s3_bucket_name" {

  value = aws_s3_bucket.wordpress_assets.bucket

}

output "cloudfront_domain" {
 value = aws_cloudfront_distribution.s3_distribution.domain_name
}


