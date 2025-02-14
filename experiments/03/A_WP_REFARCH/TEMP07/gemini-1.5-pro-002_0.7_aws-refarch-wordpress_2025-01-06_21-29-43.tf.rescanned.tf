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
  description = "The AWS region to deploy resources in."
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

variable "rds_username" {
  type        = string
  description = "The RDS instance username."
  sensitive   = true # Treat RDS username as sensitive
}


variable "rds_password" {
  type        = string
  description = "The RDS instance password."
  sensitive   = true # Treat RDS password as sensitive
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of allowed CIDR blocks for ingress rules."
  default     = ["0.0.0.0/0"] # Default to allow all, but should be restricted in production
}

variable "ami_id" {
  type = string
  description = "The ID of the AMI to use for the EC2 instance."
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

resource "aws_subnet" "public_subnet_a" {
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

resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "${var.project_name}-private-subnet-a"
    Environment = var.environment
    Project     = var.project_name
  }

}


data "aws_availability_zones" "available" {}

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


resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_route_table.id
}

# Security Groups
resource "aws_security_group" "web_sg" {
 name        = "${var.project_name}-web-sg"
  description = "Allow inbound HTTPS and SSH from authorized CIDR blocks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks = var.allowed_cidr_blocks


  }

  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
 cidr_blocks = var.allowed_cidr_blocks

  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
    description = "Allow all outbound traffic"
  }


  tags = {
    Name        = "${var.project_name}-web-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}



resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow inbound MySQL/Aurora from web security group"
 vpc_id = aws_vpc.main.id


 ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
 description = "Allow MySQL/Aurora traffic from web servers"
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
 description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
    Project     = var.project_name
  }

}


# EC2 Instances and Autoscaling
resource "aws_instance" "web_server" {
  ami                         = var.ami_id
  instance_type               = "t2.micro"
  subnet_id                  = aws_subnet.public_subnet_a.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  user_data                  = <<EOF
#!/bin/bash
sudo yum update -y
sudo yum install httpd -y
sudo systemctl start httpd
sudo systemctl enable httpd
echo "<h1>Hello from Terraform!</h1>" > /var/www/html/index.html
EOF
  associate_public_ip_address = false
  monitoring                  = true
  ebs_optimized = true # Enable EBS optimization



  tags = {
    Name        = "${var.project_name}-web-server"
    Environment = var.environment
    Project     = var.project_name
  }
}


# RDS Instance
resource "aws_db_instance" "default" {
  allocated_storage              = 20
  storage_type                   = "gp2"
  engine                         = "mysql"
  engine_version                 = "8.0.28"
  instance_class                 = "db.t2.micro"
  name                           = "wordpressdb"
  username                       = var.rds_username
  password                       = var.rds_password
  parameter_group_name           = "default.mysql8.0"
  skip_final_snapshot            = true
  vpc_security_group_ids         = [aws_security_group.rds_sg.id]
  db_subnet_group_name           = aws_db_subnet_group.default.name
  storage_encrypted              = true
  iam_database_authentication_enabled = true
 backup_retention_period = 7
 enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]



  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_a.id]

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
    Project     = var.project_name
  }
}




# Elastic Load Balancer

resource "aws_lb" "web" {
 name               = "${var.project_name}-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]

 subnets = [aws_subnet.public_subnet_a.id]

 enable_deletion_protection = true
 drop_invalid_header_fields = true

  tags = {
    Name        = "${var.project_name}-lb"
    Environment = var.environment
    Project     = var.project_name
  }
}



resource "aws_lb_target_group" "web" {
  name        = "${var.project_name}-lb-tg"
  port        = 443 # HTTPS port
  protocol    = "HTTPS" # Use HTTPS
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

 health_check {
    path                = "/"
    protocol            = "HTTPS"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
  tags = {
    Name        = "${var.project_name}-lb-tg"
    Environment = var.environment
    Project     = var.project_name
  }
}



resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.web.arn
  port              = "443" # HTTPS port
  protocol          = "HTTPS" # Use HTTPS
  ssl_policy = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn = "arn:aws:iam::123456789012:server-certificate/test_cert" # Replace with your certificate ARN
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}


resource "aws_lb_target_group_attachment" "web" {
 target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web_server.id
  port             = 443 # HTTPS port
}



# S3 Bucket
resource "aws_s3_bucket" "web_assets" {
  bucket = "${var.project_name}-s3-bucket"
 acl    = "private"

 versioning {
    enabled = true
  }
 logging {
    target_bucket = "your-s3-logging-bucket" # Replace with your logging bucket name
    target_prefix = "s3-logs/"
 }

  tags = {
    Name        = "${var.project_name}-s3-bucket"
    Environment = var.environment
    Project     = var.project_name
  }
}


# CloudFront Distribution (Basic Example)
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.web_assets.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.web_assets.id
 custom_origin_config {
      http_port = 80
      https_port = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"


  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.web_assets.id
    viewer_protocol_policy = "redirect-to-https"


    forwarded_values {
      query_string = false


      cookies {
        forward = "none"
      }
    }
  }


  price_class = "PriceClass_All"


  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }


  viewer_certificate {
 minimum_protocol_version = "TLSv1.2_2021"

  }

  tags = {
    Name        = "${var.project_name}-cloudfront"
    Environment = var.environment
    Project     = var.project_name
  }

 logging_config {
    include_cookies = false
    bucket = "your-cloudfront-logs-bucket" # Replace with your logging bucket
    prefix = "cloudfront-logs"

  }
}




# Route53 (Basic Example - Assumes you have a hosted zone)
# resource "aws_route53_record" "www" {
#   zone_id = "YOUR_HOSTED_ZONE_ID" # Replace with your hosted zone ID
#   name    = "www"
#   type    = "A"




#   alias {
#     name                   = aws_lb.web.dns_name
#     zone_id                = aws_lb.web.zone_id
#     evaluate_target_health = true
#   }
# }



output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC."
}

output "rds_endpoint" {
  value       = aws_db_instance.default.address
  description = "The endpoint of the RDS instance."
}


output "load_balancer_dns_name" {
  value       = aws_lb.web.dns_name
  description = "The DNS name of the load balancer."
}

output "s3_bucket_name" {
  value = aws_s3_bucket.web_assets.bucket
 description = "The name of the S3 bucket"
}

output "cloudfront_domain_name" {
 value = aws_cloudfront_distribution.s3_distribution.domain_name
 description = "The domain name of the CloudFront distribution."
}
