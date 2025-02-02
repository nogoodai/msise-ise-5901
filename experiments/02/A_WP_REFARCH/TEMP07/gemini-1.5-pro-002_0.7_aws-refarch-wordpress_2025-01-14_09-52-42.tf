terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.101.0/24", "10.0.102.0/24"]
}


resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "wordpress-vpc"
    Environment = "production"
  }
}

resource "aws_subnet" "public_subnets" {
  for_each = {
    for i, cidr in var.public_subnet_cidrs : i => cidr
  }

  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = each.value
  availability_zone       = data.aws_availability_zones.available.zones[each.key]
  map_public_ip_on_launch = true

  tags = {
    Name        = "wordpress-public-subnet-${each.key}"
    Environment = "production"
  }
}


resource "aws_subnet" "private_subnets" {
  for_each = {
    for i, cidr in var.private_subnet_cidrs : i => cidr
  }

  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = each.value
  availability_zone = data.aws_availability_zones.available.zones[each.key]


  tags = {
    Name        = "wordpress-private-subnet-${each.key}"
    Environment = "production"
  }
}

data "aws_availability_zones" "available" {}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "wordpress-igw"
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
  for_each       = { for subnet in aws_subnet.public_subnets : subnet.id => subnet }
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public_route_table.id
}


# Security Groups

# ... (Security group definitions for EC2, RDS, and ELB will go here)

# EC2 Instances and Auto Scaling

# ... (EC2 and Auto Scaling configurations will go here)

# RDS Instance

# ... (RDS configuration will go here)

# Elastic Load Balancer

# ... (ELB configuration will go here)

# CloudFront Distribution

# ... (CloudFront configuration will go here)

# S3 Bucket

# ... (S3 bucket configuration will go here)

# Route 53

# ... (Route 53 configuration will go here)



