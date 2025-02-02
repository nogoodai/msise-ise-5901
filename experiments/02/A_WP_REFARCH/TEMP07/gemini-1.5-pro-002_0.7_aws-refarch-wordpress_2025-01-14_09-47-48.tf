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

variable "allowed_ssh_ips" {
  type    = list(string)
  default = ["0.0.0.0/0"] # Replace with your actual IP range for SSH access
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "rds_instance_class" {
  type    = string
  default = "db.t3.micro"
}


# VPC and Networking
resource "aws_vpc" "wordpress-vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "wordpress-vpc"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.wordpress-vpc.id

  tags = {
    Name        = "wordpress-igw"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "public_subnets" {
  for_each            = { for i, cidr in var.public_subnet_cidrs : i => cidr }
  vpc_id              = aws_vpc.wordpress-vpc.id
  cidr_block          = each.value
  availability_zone   = data.aws_availability_zones.available.names[each.key]
  map_public_ip_on_launch = true
  tags = {
    Name        = "wordpress-public-subnet-${each.key}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress-vpc.id

  tags = {
    Name        = "wordpress-public-route-table"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}


resource "aws_route_table_association" "public_subnet_association" {
  for_each         = aws_subnet.public_subnets
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public_route_table.id
}



resource "aws_subnet" "private_subnets" {
  for_each          = { for i, cidr in var.private_subnet_cidrs : i => cidr }
  vpc_id            = aws_vpc.wordpress-vpc.id
  cidr_block        = each.value
  availability_zone = data.aws_availability_zones.available.names[each.key]

  tags = {
    Name        = "wordpress-private-subnet-${each.key}"
    Environment = var.environment
    Project     = var.project
  }
}

data "aws_availability_zones" "available" {}


# Security Groups

resource "aws_security_group" "web_sg" {
 name = "wordpress-web-sg"
  description = "Allow inbound HTTP, HTTPS and SSH"
 vpc_id = aws_vpc.wordpress-vpc.id

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }

  ingress {
 from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = var.allowed_ssh_ips
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name        = "wordpress-web-sg"
    Environment = var.environment
    Project     = var.project
  }
}



# ... (Rest of the resources: EC2, RDS, ALB, Autoscaling, CloudFront, S3, Route53, etc. will be added in a future iteration due to character limits)

