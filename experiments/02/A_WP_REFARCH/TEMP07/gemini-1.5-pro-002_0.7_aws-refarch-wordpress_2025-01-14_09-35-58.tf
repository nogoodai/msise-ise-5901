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

variable "tags" {
  type = map(string)
  default = {
    Environment = "production"
    Project     = "wordpress"
  }
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    var.tags,
    { Name = "wordpress-vpc" }
  )
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    { Name = "wordpress-igw" }
  )
}

# Public Subnets
resource "aws_subnet" "public" {
  for_each            = { for i, cidr in var.public_subnet_cidrs : i => cidr }
  vpc_id              = aws_vpc.main.id
  cidr_block          = each.value
  availability_zone   = data.aws_availability_zones.available.names[each.key]
  map_public_ip_on_launch = true

  tags = merge(
    var.tags,
    {
      Name = "wordpress-public-subnet-${each.key}"
    }
  )
}

# Private Subnets
resource "aws_subnet" "private" {
  for_each          = { for i, cidr in var.private_subnet_cidrs : i => cidr }
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = data.aws_availability_zones.available.names[each.key]

  tags = merge(
    var.tags,
    {
      Name = "wordpress-private-subnet-${each.key}"
    }
  )
}


data "aws_availability_zones" "available" {}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = merge(
    var.tags,
    { Name = "wordpress-public-route-table" }
  )
}

# Route Table Associations (Public)
resource "aws_route_table_association" "public" {
  for_each       = { for i, subnet_id in aws_subnet.public : i => subnet_id }
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}


# Security Groups (Placeholders - To be expanded)
resource "aws_security_group" "web" {
 name        = "wordpress-web-sg"
  description = "Allow HTTP, HTTPS and SSH access"
 vpc_id      = aws_vpc.main.id

  tags = merge(var.tags)

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


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

# ... (Rest of the required components with security best practices and configurations)



