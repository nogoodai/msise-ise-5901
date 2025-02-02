terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~5.0.0"
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

variable "environment" {
  type    = string
  default = "production"
}

variable "project" {
  type    = string
  default = "wordpress"
}


# VPC and Networking
resource "aws_vpc" "wordpress-vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "wordpress-vpc"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "public-subnet-a" {
  vpc_id            = aws_vpc.wordpress-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "public-subnet-a"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "private-subnet-a" {
  vpc_id            = aws_vpc.wordpress-vpc.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "private-subnet-a"
    Environment = var.environment
    Project     = var.project
  }
}


data "aws_availability_zones" "available" {}


resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.wordpress-vpc.id

  tags = {
    Name        = "wordpress-igw"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table" "public-route-table" {
  vpc_id = aws_vpc.wordpress-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name        = "public-route-table"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table_association" "public-subnet-association-a" {
 subnet_id      = aws_subnet.public-subnet-a.id
 route_table_id = aws_route_table.public-route-table.id
}


# Security Groups

resource "aws_security_group" "web-sg" {
  name        = "wordpress-web-sg"
  vpc_id      = aws_vpc.wordpress-vpc.id
  description = "Allow inbound HTTP, HTTPS, and SSH"

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

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Replace with your IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name        = "wordpress-web-sg"
    Environment = var.environment
    Project     = var.project
  }
}


# ... (Rest of the required components, following the same structure and best practices)

