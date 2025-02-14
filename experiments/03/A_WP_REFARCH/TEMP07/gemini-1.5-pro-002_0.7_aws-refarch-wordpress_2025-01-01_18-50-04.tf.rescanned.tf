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

variable "domain_name" {
  type        = string
  description = "The domain name to use for Route53."
}

variable "route53_zone_id" {
  type        = string
  description = "The ID of the Route53 hosted zone."
}

variable "db_username" {
  type        = string
  description = "The database username."
  default     = "admin"
}


variable "db_password" {
  type        = string
  description = "The database password.  Store this securely outside of Terraform such as AWS Secrets Manager or HashiCorp Vault"
  sensitive   = true

}


data "aws_availability_zones" "available" {}

# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  }
}


resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project_name}-public-subnet-1"
    Environment = var.environment
  }
}

resource "aws_subnet" "public_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  tags = {
    Name        = "${var.project_name}-public-subnet-2"
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
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



# Security Groups

resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow HTTPS access from the internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] # Open to all IPs for now. Replace with appropriate CIDR block in production environment.
    ipv6_cidr_blocks = ["::/0"]  # Open to all IPs for now. Replace with appropriate CIDR block in production environment.

    description = "Allow HTTPS traffic from the internet"
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
    Name        = "${var.project_name}-alb-sg"
    Environment = var.environment
  }
}


resource "aws_security_group" "ec2_sg" {
  name        = "${var.project_name}-ec2-sg"
  description = "Allow HTTP and HTTPS access from ALB"
  vpc_id      = aws_vpc.main.id


  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
    description      = "Allow HTTP traffic from the ALB"

  }
  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
    description      = "Allow HTTPS traffic from the ALB"

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
    Name        = "${var.project_name}-ec2-sg"
    Environment = var.environment
  }
}


# EC2 Instances and Auto Scaling

resource "aws_launch_template" "wordpress" {


  name_prefix   = "${var.project_name}-launch-template-"
  image_id      = "ami-0c94855ba95c574c8" # Example AMI, replace with your desired AMI
  instance_type = "t2.micro"

  network_interfaces {
    security_groups = [aws_security_group.ec2_sg.id]


  }


  user_data = <<EOF
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
    Name        = "${var.project_name}-launch-template"
    Environment = var.environment
  }

}

resource "aws_autoscaling_group" "wordpress" {

  vpc_zone_identifier = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  launch_template {
    id      = aws_launch_template.wordpress.id
    version = "$Latest"
  }


  min_size                  = 2
  max_size                  = 4
  health_check_grace_period = 300
  health_check_type         = "ELB"
  target_group_arns         = [aws_lb_target_group.wordpress.arn]


  tag {
    key                 = "Name"
    value               = "${var.project_name}-asg"
    propagate_at_launch = true
  }
  tags = {
    Name        = "${var.project_name}-asg"
    Environment = var.environment
  }


}



# Load Balancer

resource "aws_lb" "wordpress_lb" {
  name                    = "${var.project_name}-lb"
  internal                = false
  load_balancer_type      = "application"
  security_groups         = [aws_security_group.alb_sg.id]
  subnets                = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  enable_deletion_protection = true
 drop_invalid_header_fields = true
  tags = {
    Name        = "${var.project_name}-alb"
    Environment = var.environment
  }
}


resource "aws_lb_target_group" "wordpress" {
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
  }
}



resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.wordpress_lb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01" # Enforce TLS 1.2 or higher
  certificate_arn   = var.certificate_arn # Use a valid ACM certificate ARN

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}

variable "certificate_arn" {
  type = string
  description = "ARN of the SSL certificate from ACM."

}




# RDS Instance

resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.public_1.id, aws_subnet.public_2.id] # Ideally, use private subnets


  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
  }
}


resource "aws_db_instance" "default" {
  allocated_storage                = 20
  storage_type                     = "gp2"
  engine                           = "mysql"
  engine_version                   = "8.0" # Or your preferred version
  instance_class                   = "db.t2.micro"
  name                             = "wordpress"
  username                         = var.db_username
  password                         = var.db_password
  db_subnet_group_name             = aws_db_subnet_group.default.name
  skip_final_snapshot              = true
  publicly_accessible              = false
  storage_encrypted                = true
  backup_retention_period          = 7 # Set to a value greater than 0
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports    = ["audit", "error", "general", "slowquery"] # Enable relevant logs



  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
  }
}



# S3 Bucket
resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "${var.project_name}-assets"
  acl    = "private"

  versioning {
    enabled = true
  }

  logging {
    target_bucket = "your-log-bucket-name" # Replace with your log bucket name
    target_prefix = "s3-logs/${var.project_name}-assets/"
  }


  tags = {
    Name        = "${var.project_name}-s3"
    Environment = var.environment
  }
}


# CloudFront Distribution (Example with S3 origin)
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.wordpress_assets.bucket

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2", "TLSv1.1", "TLSv1"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html" # Or your default object

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.wordpress_assets.bucket

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl           = 86400
    max_ttl               = 31536000
  }

  price_class = "PriceClass_All" # Or your desired price class

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name        = "${var.project_name}-cloudfront"
    Environment = var.environment
  }

  viewer_certificate {
    minimum_protocol_version = "TLSv1.2_2021"

  }
}


resource "aws_route53_record" "cloudfront_record" {
  zone_id = var.route53_zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = true
  }
}


output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.s3_distribution.domain_name
  description = "The CloudFront domain name."
}

output "load_balancer_dns_name" {
  value       = aws_lb.wordpress_lb.dns_name
  description = "The load balancer DNS name."
}

output "rds_endpoint" {
  value       = aws_db_instance.default.endpoint
  description = "The RDS endpoint."
}
