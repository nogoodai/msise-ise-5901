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

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of allowed CIDR blocks for ingress rules."
  default     = []
}


# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  }


}

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name        = "${var.project_name}-public-subnet-${count.index}"
    Environment = var.environment
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 2)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name        = "${var.project_name}-private-subnet-${count.index}"
    Environment = var.environment
  }
}

data "aws_availability_zones" "available" {}

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

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}


# Security Groups
resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow HTTP, HTTPS and SSH inbound traffic"
  vpc_id      = aws_vpc.main.id



  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = var.allowed_cidr_blocks
    description      = "HTTPS access from allowed CIDR blocks"
  }
  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = var.allowed_cidr_blocks
    description      = "HTTP access from allowed CIDR blocks"
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"

  }

  tags = {
    Name        = "${var.project_name}-web-sg"
    Environment = var.environment
  }
}


# EC2 Instances and Autoscaling
resource "aws_launch_template" "wordpress_lt" {
  name_prefix = "${var.project_name}-wordpress-lt-"

  network_interfaces {
    security_groups = [aws_security_group.web_sg.id]
  }

  tags = {
    Name        = "${var.project_name}-wordpress-lt"
    Environment = var.environment
  }

 update_default_version = true
}


# Placeholder for RDS, ELB, CloudFront, S3, and Route53.  These would require significantly more details from the user to configure properly, but the basic structure is shown below.

# RDS Instance
resource "aws_db_instance" "default" {

  storage_encrypted          = true
  backup_retention_period    = 12
  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]
  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
  }

 # ... other required RDS configurations
}

# Elastic Load Balancer
resource "aws_lb" "default" {

  enable_deletion_protection = true
  drop_invalid_header_fields = true
 tags = {
    Name        = "${var.project_name}-alb"
    Environment = var.environment
  }


 # ... other required ALB configurations
}


# CloudFront Distribution
resource "aws_cloudfront_distribution" "default" {

  viewer_certificate {
    cloudfront_default_certificate = true # Placeholder - Replace with actual certificate in production
  }
 tags = {
    Name        = "${var.project_name}-cloudfront"
    Environment = var.environment
  }
 enabled = true

  # ... other required CloudFront configurations
}

# S3 Bucket
resource "aws_s3_bucket" "default" {

 versioning {
    enabled = true
 }

 logging {
 target_bucket = "your-logging-bucket-here" # Replace with your S3 logging bucket name
    target_prefix = "log/"
 }

  tags = {
    Name        = "${var.project_name}-s3"
    Environment = var.environment
  }

  # ... other required S3 configurations
}


# Route53 Record
resource "aws_route53_record" "default" {

 # ... other required Route53 configurations
}



