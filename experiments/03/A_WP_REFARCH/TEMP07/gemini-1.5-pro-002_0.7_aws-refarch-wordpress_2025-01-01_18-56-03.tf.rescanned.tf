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
  description = "The AWS region to deploy into."
  default     = "us-west-2"
}

variable "project_name" {
  type        = string
  description = "The name of the project."
  default     = "wordpress-project"
}

variable "environment" {
  type        = string
  description = "The environment name (e.g., production, development)."
  default     = "production"
}


variable "rds_username" {
  type        = string
  description = "The RDS instance username."
  default     = "admin"
}


variable "rds_password" {
  type        = string
  description = "The RDS instance password."
  sensitive   = true

}



variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of allowed CIDR blocks for SSH access to web servers."
  default     = []

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

resource "aws_subnet" "public_subnet_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project_name}-public-subnet-a"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
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
  description = "Allow inbound HTTPS and SSH from specific CIDRs, and all outbound traffic."
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    description      = "Allow HTTPS from anywhere"

  }

  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = var.allowed_cidr_blocks
    description      = "Allow SSH from allowed CIDRs"

  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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
  description = "Allow inbound traffic from web servers, and all outbound traffic."
  vpc_id      = aws_vpc.main.id


 ingress {
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
    security_groups = [aws_security_group.web_sg.id]
    description      = "Allow MySQL access from web servers"


  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    description      = "Allow all outbound traffic"


  }

  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}


# EC2 Instances

resource "aws_instance" "web_server" {
  ami                         = "ami-0c94855ba95c574c8" # Replace with your desired AMI
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnet_a.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  associate_public_ip_address = false
  monitoring                  = true
  ebs_optimized               = true



  user_data = <<-EOF
#!/bin/bash
sudo yum update -y
sudo amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2
sudo yum install -y httpd mariadb-server
sudo systemctl start httpd
sudo systemctl enable httpd
sudo systemctl start mariadb
sudo systemctl enable mariadb
EOF


  tags = {
    Name        = "${var.project_name}-web-server"
    Environment = var.environment
    Project     = var.project_name

  }
}


# RDS Instance

resource "aws_db_instance" "wordpress_db" {
  allocated_storage                = 20
  storage_type                     = "gp2"
  engine                           = "mysql"
  engine_version                   = "8.0"
  instance_class                   = "db.t2.micro"
  name                             = "wordpressdb"
  username                         = var.rds_username
  password                         = var.rds_password
  db_subnet_group_name             = aws_db_subnet_group.default.name
  vpc_security_group_ids           = [aws_security_group.rds_sg.id]
  skip_final_snapshot              = true
  storage_encrypted                = true
  iam_database_authentication_enabled = true
  backup_retention_period           = 7
 enabled_cloudwatch_logs_exports    = ["audit", "error", "general", "slowquery"]


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

resource "aws_lb" "web_lb" {
  name                       = "${var.project_name}-web-lb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.web_sg.id]
  subnets                    = [aws_subnet.public_subnet_a.id]
  enable_deletion_protection = true
 drop_invalid_header_fields = true
  tags = {
    Name        = "${var.project_name}-web-lb"
    Environment = var.environment
    Project     = var.project_name
  }

}



resource "aws_lb_target_group" "web_tg" {
  name        = "${var.project_name}-web-tg"
  port        = 443 # Changed to HTTPS port
  protocol    = "HTTPS" # Changed to HTTPS
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTPS" # Changed to HTTPS
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 5
    timeout             = 5
    matcher             = "200"
  }
 tags = {
    Name        = "${var.project_name}-web-tg"
    Environment = var.environment
    Project     = var.project_name
  }


}


resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.web_lb.arn
  port              = "443" # Changed to HTTPS port
  protocol          = "HTTPS" # Changed to HTTPS
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01" # Enforce TLS 1.2 or higher
 default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}



# Auto Scaling Group
resource "aws_autoscaling_group" "web_asg" {
  name                 = "${var.project_name}-web-asg"
  min_size             = 1
 max_size             = 3
  desired_capacity    = 1
  health_check_type    = "ELB"
  health_check_grace_period = 300
 vpc_zone_identifier = [aws_subnet.public_subnet_a.id]
  target_group_arns = [aws_lb_target_group.web_tg.arn]

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }


  tag {
    key                 = "Name"
    value               = "${var.project_name}-web-asg"
    propagate_at_launch = true
  }
}



resource "aws_launch_template" "web" {
  name = "${var.project_name}-launch-template"


  instance_market_options {
    market_type = "spot"
  }

  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination       = true
    security_groups             = [aws_security_group.web_sg.id]
  }

  image_id      = "ami-0c94855ba95c574c8" # Replace with your desired AMI
  instance_type = "t2.micro"
  tag_specifications {
    resource_type = "instance"

    tags = {
      Name        = "${var.project_name}-web-server-instance"
      Environment = var.environment
      Project     = var.project_name
    }
  }



}


# S3 Bucket
resource "aws_s3_bucket" "static_assets" {
  bucket = "${var.project_name}-static-assets"
  acl    = "private"

  versioning {
    enabled = true
  }
  logging {
 target_bucket = "your-log-bucket" # Replace with your log bucket name
 target_prefix = "log/"
  }



  tags = {
    Name        = "${var.project_name}-s3"
    Environment = var.environment
    Project     = var.project_name
  }
}


# CloudFront Distribution (Basic Example - Configure as needed)

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.static_assets.website_endpoint
    origin_id   = aws_s3_bucket.static_assets.bucket

  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.static_assets.bucket

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

  price_class = "PriceClass_All"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
 cloudfront_default_certificate = false
 minimum_protocol_version = "TLSv1.2_2021"
  }

  logging_config {
    include_cookies = false
 bucket          = "your-logs-bucket.s3.amazonaws.com" # Replace with your logging bucket domain

    prefix = "cf-logs/"


  }



  tags = {
    Name        = "${var.project_name}-cloudfront"
    Environment = var.environment
    Project     = var.project_name
  }
}


# Route53 (requires a hosted zone - replace with your zone ID)
# resource "aws_route53_record" "www" {
#  zone_id = "YOUR_HOSTED_ZONE_ID"
#  name    = "www.example.com" # Replace with your domain
#  type    = "A"


#  alias {
#    name                   = aws_lb.web_lb.dns_name
#    zone_id                = aws_lb.web_lb.zone_id
#    evaluate_target_health = true
#  }
# }

output "load_balancer_dns_name" {
  value       = aws_lb.web_lb.dns_name
  description = "The DNS name of the load balancer."
}


output "s3_bucket_arn" {
  value       = aws_s3_bucket.static_assets.arn
  description = "The ARN of the S3 bucket."
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.s3_distribution.domain_name
  description = "The domain name of the CloudFront distribution."
}

output "rds_endpoint" {
  value       = aws_db_instance.wordpress_db.endpoint
  description = "The endpoint of the RDS instance."
}


