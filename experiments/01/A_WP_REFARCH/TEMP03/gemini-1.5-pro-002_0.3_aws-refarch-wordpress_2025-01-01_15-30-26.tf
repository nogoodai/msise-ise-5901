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

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_route_table.id
}


data "aws_availability_zones" "available" {}

# Security Groups

# EC2 Instances
resource "aws_instance" "wordpress_instance" {
  ami           = "ami-0c94855ba95c574c8" # Example AMI, replace with your desired AMI
  instance_type = "t2.micro"


  tags = {
    Name        = "${var.project_name}-wordpress-instance"
    Environment = var.environment
    Project     = var.project_name
  }
}


# RDS Instance

# Elastic Load Balancer

# Auto Scaling Group

# CloudFront Distribution

# S3 Bucket
resource "aws_s3_bucket" "static_assets" {
  bucket = "${var.project_name}-static-assets"

  tags = {
    Name        = "${var.project_name}-s3-bucket"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Route 53 DNS Configuration


output "s3_bucket_arn" {
  value = aws_s3_bucket.static_assets.arn
}

