terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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


resource "aws_internet_gateway" "main" {
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
    gateway_id = aws_internet_gateway.main.id
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
 name        = "${var.project_name}-web-server-sg"
 description = "Allow inbound HTTP, HTTPS, and SSH"
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
    Name        = "${var.project_name}-web-server-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}



# EC2 Instances and Auto Scaling

resource "aws_launch_configuration" "wordpress_lc" {


  image_id            = "ami-03cf3903ba8693491" # Example AMI
  instance_type       = "t2.micro"


  security_groups = [aws_security_group.web_server_sg.id]

  user_data = <<EOF
#!/bin/bash
sudo yum update -y
sudo yum install httpd php mysql -y
sudo systemctl start httpd
sudo systemctl enable httpd
sudo echo "<?php phpinfo(); ?>" > /var/www/html/info.php

EOF




 lifecycle {
   create_before_destroy = true
 }
}


resource "aws_autoscaling_group" "wordpress_asg" {

 desired_capacity   = 2
 max_size          = 4
 min_size          = 2
 launch_configuration = aws_launch_configuration.wordpress_lc.name

 vpc_zone_identifier = [aws_subnet.public_1.id, aws_subnet.public_2.id]


  tag {
    key                 = "Name"
    value              = "${var.project_name}-asg"
    propagate_at_launch = true
  }
}




# RDS Instance
resource "aws_db_instance" "default" {
  allocated_storage      = 20
  db_name                = "wordpress"
  engine                 = "mysql"
  engine_version         = "8.0" # Or latest
  identifier             = "${var.project_name}-rds"
  instance_class         = "db.t3.micro"
  username               = "admin" # Replace with a strong password
  password               = "password" # Replace with a strong password
  parameter_group_name   = "default.mysql8.0" # Adjust as needed
  publicly_accessible    = false
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.web_server_sg.id] # Update if a separate DB SG is used

  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
    Project     = var.project_name
  }

}





# Elastic Load Balancer

resource "aws_lb" "wordpress_lb" {
 name               = "${var.project_name}-lb"

 internal           = false
 load_balancer_type = "application"

 security_groups    = [aws_security_group.web_server_sg.id]
 subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]



  tags = {
    Name        = "${var.project_name}-alb"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_lb_target_group" "wordpress_tg" {

 name        = "${var.project_name}-tg"
 port        = 80
 protocol    = "HTTP"
 target_type = "instance"

 vpc_id      = aws_vpc.main.id



 health_check {
   path                    = "/"
 healthy_threshold      = 2
 unhealthy_threshold      = 2
 timeout                 = 5
 interval                = 30
 matcher                 = "200"
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


resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.wordpress_asg.name
  lb_target_group_arn     = aws_lb_target_group.wordpress_tg.arn
}



# S3 Bucket for Static Assets

resource "aws_s3_bucket" "static_assets" {
  bucket = "${var.project_name}-static-assets"
  acl    = "private"



  tags = {
    Name        = "${var.project_name}-s3-bucket"
    Environment = var.environment
    Project     = var.project_name
  }
}





# Cloudfront Distribution
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.static_assets.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.static_assets.bucket

    s3_origin_config {
      origin_access_identity = ""
    }
  }

 enabled             = true
 is_ipv6_enabled     = true


  default_cache_behavior {
    allowed_methods = ["GET", "HEAD"]



    cached_methods  = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.static_assets.bucket



    viewer_protocol_policy = "redirect-to-https"
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
}


#Route53
resource "aws_route53_zone" "primary" {
  name = "example.com" # Replace with your domain

  tags = {
    Name        = "${var.project_name}-route53-zone"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "www"
  type    = "A"



 alias {
   name                   = aws_lb.wordpress_lb.dns_name
   zone_id                = aws_lb.wordpress_lb.zone_id
   evaluate_target_health = true
 }
}


output "alb_dns_name" {
 value = aws_lb.wordpress_lb.dns_name
}

output "s3_bucket_name" {
 value = aws_s3_bucket.static_assets.bucket
}



