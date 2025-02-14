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
  description = "The AWS region to deploy resources in."
  default     = "us-west-2"
}

variable "project_name" {
  type        = string
  description = "The name of the project."
  default     = "wordpress-project"
}

variable "environment" {
  type        = string
  description = "The environment (e.g., dev, prod)."
  default     = "dev"
}

variable "db_username" {
  type        = string
  description = "The database username."
  default     = "admin"
}

variable "db_password" {
 type        = string
  description = "The database password."
  sensitive   = true
}

variable "key_name" {
  type        = string
  description = "The name of the EC2 key pair."
  sensitive   = true
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of allowed CIDR blocks."
  default = ["0.0.0.0/0"]
}

variable "ami_id" {
  type        = string
  description = "The ID of the AMI to use for EC2 instances."
  default     = "ami-0c94855ba95c574c8" # Replace with appropriate AMI ID
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

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
 map_public_ip_on_launch = false

  tags = {
    Name        = "${var.project_name}-public-subnet-1"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "${var.project_name}-private-subnet-1"
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

resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_route_table.id
}

data "aws_availability_zones" "available" {}

# Security Groups

resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow inbound HTTPS and restrict SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = var.allowed_cidr_blocks
    description      = "Allow HTTPS from allowed CIDR blocks"
  }

 ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] # Restrict SSH Access. Example of private network
    description = "Allow SSH from the VPC CIDR block"
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
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
  description = "Allow inbound traffic from web servers"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
    security_groups = [aws_security_group.web_sg.id]
 description      = "Allow MySQL traffic from web servers"

  }


  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}


# EC2 Instances & Autoscaling

resource "aws_instance" "web_server" {

  ami                    = var.ami_id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  user_data              = file("user_data.sh")
  key_name               = var.key_name
  ebs_optimized          = true
  monitoring             = true


  tags = {
    Name        = "${var.project_name}-web-server"
    Environment = var.environment
    Project     = var.project_name
  }
}



resource "aws_launch_configuration" "example" {
  image_id            = var.ami_id
  instance_type        = "t2.micro"
  key_name             = var.key_name
  security_groups      = [aws_security_group.web_sg.id]
  user_data            = file("user_data.sh")

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "example" {
  desired_capacity    = 2
  max_size            = 4
  min_size            = 2
  launch_configuration = aws_launch_configuration.example.name
  vpc_zone_identifier  = [aws_subnet.public_1.id]
  load_balancers        = [aws_lb.example.name]


  tag {
    key                 = "Name"
    value               = "${var.project_name}-asg"
    propagate_at_launch = true
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }

}


# RDS Instance

resource "aws_db_instance" "default" {
  allocated_storage          = 20
  storage_type               = "gp2"
  engine                     = "mysql"
  engine_version            = "8.0.28"
  instance_class            = "db.t2.micro"
  name                      = "wordpressdb"
  username                   = var.db_username
  password                   = var.db_password
  parameter_group_name       = "default.mysql8.0"
  skip_final_snapshot        = true
  vpc_security_group_ids     = [aws_security_group.rds_sg.id]
  db_subnet_group_name       = aws_db_subnet_group.default.name
  storage_encrypted          = true
  backup_retention_period     = 7
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports    = ["audit", "error", "general", "slowquery"]

  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
    Project     = var.project_name
  }


}



resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_1.id]

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
    Project     = var.project_name
  }
}


# Elastic Load Balancer

resource "aws_lb" "example" {
  name                       = "${var.project_name}-lb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.web_sg.id]
  subnets                    = [aws_subnet.public_1.id]
  enable_deletion_protection = true
 drop_invalid_header_fields = true


  tags = {
    Name        = "${var.project_name}-lb"
    Environment = var.environment
    Project     = var.project_name
  }

}


resource "aws_lb_target_group" "example" {
  name        = "${var.project_name}-lb-tg"
  port        = 443
  protocol    = "HTTPS"
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
        Name        = "${var.project_name}-lb-tg"
        Environment = var.environment
        Project     = var.project_name
    }
}



resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.example.arn
  port              = 443
  protocol         = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:iam::xxxxxxxxxxxx:server-certificate/test_cert" # Replace with your certificate ARN
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.example.arn
  }
}



resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = 80
  protocol         = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}


resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.example.name
  lb_target_group_arn     = aws_lb_target_group.example.arn
}




# S3 Bucket

resource "aws_s3_bucket" "example" {
  bucket = "${var.project_name}-s3-bucket"
  acl    = "private"

  versioning {
    enabled = true
  }


  logging {
    target_bucket = "your-logging-bucket-name" # Replace with your logging bucket
    target_prefix = "log/"
  }

  tags = {
    Name        = "${var.project_name}-s3-bucket"
    Environment = var.environment
    Project     = var.project_name
  }


}




# CloudFront Distribution (Basic -  Expand as needed)


resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.example.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.example.bucket

    s3_origin_config {
      origin_access_identity = "origin-access-identity/cloudfront/ABCDEFG1234567" # Replace with your OAI
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"
  default_root_object = "index.html"

  default_cache_behavior {

    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.example.bucket
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
    Environment = var.environment
    Project     = var.project_name
  }

}






# Route53 (Requires a hosted zone - replace with your zone ID)

# resource "aws_route53_record" "example" {
#   zone_id = "Z1234567890" # Replace with your hosted zone ID
#   name    = "example.com"
#   type    = "A"


#   alias {
#     name                   = aws_lb.example.dns_name
#     zone_id                = aws_lb.example.zone_id
#     evaluate_target_health = true
#   }
# }


output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC"
}


output "rds_endpoint" {
  value       = aws_db_instance.default.endpoint
  description = "The endpoint of the RDS instance"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.example.bucket
  description = "The name of the S3 bucket"
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.s3_distribution.domain_name
  description = "The domain name of the CloudFront distribution"
}

output "load_balancer_dns_name" {
  value       = aws_lb.example.dns_name
  description = "The DNS name of the load balancer"
}


