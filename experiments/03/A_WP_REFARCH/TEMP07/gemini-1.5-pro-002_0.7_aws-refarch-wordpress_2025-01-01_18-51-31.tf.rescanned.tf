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
  type        = string
  description = "The AWS region to deploy the resources in."
  default     = "us-west-2"
}

variable "vpc_cidr" {
  type        = string
  description = "The CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "The CIDR blocks for the public subnets."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "The CIDR blocks for the private subnets."
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "availability_zones" {
  type        = list(string)
  description = "The availability zones to deploy the resources in."
  default     = ["us-west-2a", "us-west-2b"]
}

variable "instance_type" {
  type        = string
  description = "The instance type for the EC2 instances."
  default     = "t3.micro"
}

variable "rds_instance_class" {
  type        = string
  description = "The instance class for the RDS instance."
  default     = "db.t3.micro"
}


variable "rds_username" {
  type        = string
  description = "The username for the RDS instance."
  default     = "admin"
}


variable "rds_password" {
  type        = string
  description = "The password for the RDS instance."
  sensitive   = true

}

variable "allowed_cidr_blocks" {
 type = list(string)
 description = "List of CIDR blocks allowed to access web servers."
 default = ["0.0.0.0/0"]
}

variable "db_backup_retention_period" {
  type = number
  description = "Backup retention period for RDS"
  default = 7
}

variable "ami_id" {
  type = string
  description = "AMI ID for EC2 instances"
}



data "aws_ami" "amazon_linux" {
 most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
 values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }


}



# VPC and Networking
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "wordpress-vpc"
    Environment = "production"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "wordpress-igw"
    Environment = "production"
  }
}


resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "wordpress-public-subnet-${count.index}"
    Environment = "production"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "wordpress-private-subnet-${count.index}"
    Environment = "production"
  }
}



resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name        = "wordpress-public-route-table"
    Environment = "production"
  }
}


resource "aws_route_table_association" "public_subnet_association" {
 count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}



# Security Groups


resource "aws_security_group" "web_sg" {
  name        = "wordpress-web-sg"
  description = "Allow inbound HTTPS and SSH"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Allow HTTPS from allowed CIDR blocks"

  }

 ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["172.18.0.0/16"] # Replace with your IP
        description = "Allow SSH from my network"

  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
    description = "Allow all outbound traffic"
  }


  tags = {
    Name        = "wordpress-web-sg"
    Environment = "production"
  }
}



resource "aws_security_group" "rds_sg" {
  name        = "wordpress-rds-sg"
  description = "Allow inbound traffic from web servers"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
    security_groups = [aws_security_group.web_sg.id]
    description = "Allow MySQL traffic from web security group"

  }

  tags = {
    Name        = "wordpress-rds-sg"
    Environment = "production"
  }
}




# EC2 Instances


resource "aws_instance" "wordpress_instances" {
  count         = 2
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id = aws_subnet.public_subnets[count.index].id

  vpc_security_group_ids = [aws_security_group.web_sg.id]
  monitoring = true

    user_data = <<-EOF
#!/bin/bash
yum update -y
yum install httpd php mysql php-mysql -y
systemctl start httpd
systemctl enable httpd
echo "<?php phpinfo(); ?>" > /var/www/html/index.php

  EOF


  tags = {
    Name        = "wordpress-instance-${count.index}"
    Environment = "production"
  }
}




# RDS Instance


resource "aws_db_instance" "wordpress_db" {
  identifier               = "wordpress-db"
 allocated_storage        = 20
  storage_type             = "gp2"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = var.rds_instance_class
  username                = var.rds_username
  password                = var.rds_password
  db_subnet_group_name    = aws_db_subnet_group.default.name
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  skip_final_snapshot     = true
  delete_automated_backups = true
  storage_encrypted = true
  backup_retention_period = var.db_backup_retention_period
  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]


  tags = {
    Name        = "wordpress-db"
    Environment = "production"
  }
}

resource "aws_db_subnet_group" "default" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private_subnets[*].id

  tags = {
    Name        = "main"
    Environment = "production"
  }
}









# Elastic Load Balancer

resource "aws_lb" "wordpress_lb" {
  name               = "wordpress-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
 subnets = aws_subnet.public_subnets[*].id
 enable_deletion_protection = true
 drop_invalid_header_fields = true



  tags = {
    Name        = "wordpress-lb"
    Environment = "production"
  }

}



resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.wordpress_lb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy = "ELBSecurityPolicy-TLS-1-2-Ext-2018-06"
 certificate_arn = "arn:aws:iam::123456789012:server-certificate/test_cert_rab3wuqxz"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}


resource "aws_lb_target_group" "wordpress_tg" {
  name        = "wordpress-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.wordpress_vpc.id
  target_type = "instance"

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5

  }

}



resource "aws_lb_target_group_attachment" "wordpress_tg_attachment" {
  count            = length(aws_instance.wordpress_instances)
  target_group_arn = aws_lb_target_group.wordpress_tg.arn
  target_id        = aws_instance.wordpress_instances[count.index].id
  port             = 80
}


#  S3 Bucket

resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-bucket-${random_id.bucket_id.hex}"
 acl    = "private"

  versioning {
 enabled = true
  }

  logging {
    target_bucket = "your-s3-logging-bucket" # Replace with an existing bucket name
    target_prefix = "log/"
  }
 server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Name        = "wordpress-bucket"
    Environment = "production"
  }

}

resource "random_id" "bucket_id" {
  byte_length = 8
}


# Cloudfront Distribution


resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_lb.wordpress_lb.dns_name
    origin_id   = "wordpress-lb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # or match-viewer
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"


  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-lb"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }



  price_class = "PriceClass_100"



  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }


  viewer_certificate {
    minimum_protocol_version = "TLSv1.2_2021"

  }
 tags = {
    Name        = "cloudfront-dist"
    Environment = "production"

 }


}



# Route53


resource "aws_route53_zone" "wordpress_zone" {
 name = "example.com" # Replace with your domain name
 tags = {
    Name = "route53-zone"
  }

}




resource "aws_route53_record" "wordpress_record" {
 zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "wordpress"
  type    = "A"


 alias {
    name                   = aws_lb.wordpress_lb.dns_name
    zone_id                = aws_lb.wordpress_lb.zone_id
    evaluate_target_health = true
  }
}



output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.wordpress_cdn.domain_name
  description = "The domain name of the CloudFront distribution."
}


output "lb_dns_name" {
  value       = aws_lb.wordpress_lb.dns_name
 description = "The DNS name of the load balancer."

}


output "rds_endpoint" {
  value       = aws_db_instance.wordpress_db.endpoint
  description = "The endpoint of the RDS instance."
}



