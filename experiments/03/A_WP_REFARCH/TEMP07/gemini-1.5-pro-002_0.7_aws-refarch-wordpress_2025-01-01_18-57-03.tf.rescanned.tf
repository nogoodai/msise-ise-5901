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
  type        = string
  default     = "us-west-2"
  description = "The AWS region to deploy the resources in."
}

variable "project_name" {
  type        = string
  default     = "wordpress-project"
  description = "The name of the project."
}

variable "environment" {
  type        = string
  default     = "production"
  description = "The environment name (e.g., production, development)."

}

variable "db_password" {
  type        = string
  description = "Password for the RDS database. Must be strong and stored securely."
  sensitive   = true
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of CIDR blocks allowed to access the web servers."
  default     = []
}

variable "ssh_allowed_cidr_blocks" {
  type        = list(string)
  description = "List of CIDR blocks allowed to SSH to the web servers."
  default     = []

}


# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
 map_public_ip_on_launch = false

  tags = {
    Name        = "${var.project_name}-public-subnet-a"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "${var.project_name}-private-subnet-a"
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

resource "aws_route_table" "public_route_table" {
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

resource "aws_route_table_association" "public_subnet_association_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_route_table.id
}


data "aws_availability_zones" "available" {}

# Security Groups

resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow inbound HTTPS and SSH"
  vpc_id      = aws_vpc.main.id


  ingress {
    description      = "HTTPS from allowed CIDR blocks"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = var.allowed_cidr_blocks
    ipv6_cidr_blocks = []
  }


  ingress {
    description      = "SSH from allowed CIDR blocks"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = var.ssh_allowed_cidr_blocks
 ipv6_cidr_blocks = []
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
    description      = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${var.project_name}-web-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_security_group" "rds_sg" {
 name        = "${var.project_name}-rds-sg"
  description = "Allow inbound MySQL/Aurora"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
 security_groups = [aws_security_group.web_sg.id]
    description      = "Allow MySQL/Aurora traffic from web security group"
  }
  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}




# EC2 Instances & Autoscaling

resource "aws_launch_configuration" "wordpress_lc" {
  name_prefix                 = "${var.project_name}-lc-"
  image_id                    = "ami-0c94855ba95c574c8" # Replace with your desired AMI
  instance_type               = "t2.micro"
  security_groups             = [aws_security_group.web_sg.id]

  user_data = <<-EOF
#!/bin/bash
sudo yum update -y
sudo yum install httpd php mysql php-mysql -y
sudo systemctl start httpd
sudo systemctl enable httpd
sudo echo "<?php phpinfo(); ?>" > /var/www/html/index.php
  EOF


  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "${var.project_name}-asg"
  min_size                  = 2
  max_size                  = 4
 launch_configuration      = aws_launch_configuration.wordpress_lc.name
 vpc_zone_identifier       = [aws_subnet.public_a.id]
  health_check_grace_period = 300
 health_check_type         = "ELB"
  load_balancers            = [aws_lb.wordpress_lb.name]


  tag {
    key                 = "Name"
    value               = "${var.project_name}-ec2-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }


  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }



}



# RDS Instance

resource "aws_db_instance" "default" {


  identifier                 = "${var.project_name}-rds"
  allocated_storage          = 20
  storage_type               = "gp2"
  engine                     = "mysql"
  engine_version             = "8.0" # Replace with your desired version
  instance_class             = "db.t2.micro"
  username                   = "admin" # Replace with your desired username
  password                   = var.db_password
  db_subnet_group_name       = aws_db_subnet_group.default.name
  vpc_security_group_ids     = [aws_security_group.rds_sg.id]
  skip_final_snapshot        = true
  multi_az                   = false
  storage_encrypted          = true
  backup_retention_period     = 7 # Set to a value greater than 0
  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]
  iam_database_authentication_enabled = true



  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
    Project     = var.project_name
  }
}
resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id]

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
    Project     = var.project_name
  }
}



# Load Balancer

resource "aws_lb" "wordpress_lb" {
  name                    = "${var.project_name}-lb"
  internal                = false
  load_balancer_type      = "application"
  security_groups         = [aws_security_group.web_sg.id]
 subnets                  = [aws_subnet.public_a.id]
  enable_deletion_protection = true
  drop_invalid_header_fields = true


  tags = {
    Name        = "${var.project_name}-lb"
    Environment = var.environment
    Project     = var.project_name
  }
}



resource "aws_lb_target_group" "wordpress_tg" {
  name        = "${var.project_name}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"


  health_check {
    path                = "/"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
 timeout             = 5
  }

  tags = {
    Name        = "${var.project_name}-tg"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress_lb.arn
  port              = 80
  protocol          = "HTTP"



  default_action {
    type             = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}



resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.wordpress_asg.name
  lb_target_group_arn     = aws_lb_target_group.wordpress_tg.arn
}



# S3 Bucket


resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "${var.project_name}-s3-bucket"
  acl    = "private"



  versioning {
    enabled = true
  }


  logging {
    target_bucket = "${var.project_name}-s3-bucket-logs" # Replace with a dedicated logging bucket
 target_prefix = "logs/"
  }

  tags = {
    Name        = "${var.project_name}-s3-bucket"
    Environment = var.environment
    Project     = var.project_name
  }


}

resource "aws_s3_bucket" "wordpress_bucket_logs" {
  bucket = "${var.project_name}-s3-bucket-logs"
  acl    = "log-delivery-write"


}



# Cloudfront Distribution (Basic Configuration)

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.wordpress_bucket.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.wordpress_bucket.bucket


    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2", "TLSv1.3"]

    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html" # Replace with your default object if needed


  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.wordpress_bucket.bucket

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

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
    minimum_protocol_version = "TLSv1.2_2021"
  }


  tags = {
    Name        = "${var.project_name}-cloudfront-distribution"
    Environment = var.environment
    Project     = var.project_name
  }
}







# Outputs


output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC."
}

output "load_balancer_dns_name" {
 value       = aws_lb.wordpress_lb.dns_name
  description = "The DNS name of the load balancer."
}

output "s3_bucket_arn" {
  value       = aws_s3_bucket.wordpress_bucket.arn
  description = "The ARN of the S3 bucket."
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.s3_distribution.domain_name
  description = "The domain name of the CloudFront distribution."
}



output "rds_endpoint" {
  value       = aws_db_instance.default.endpoint
  description = "The endpoint of the RDS instance."
}


