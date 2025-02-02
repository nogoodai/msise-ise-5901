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

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}


# VPC and Networking
resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "wordpress-vpc"
    Environment = "production"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "wordpress-igw"
    Environment = "production"
  }
}


resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "wordpress-public-subnet-${count.index + 1}"
    Environment = "production"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index + length(var.public_subnet_cidrs)] # Use different AZs for private subnets

  tags = {
    Name        = "wordpress-private-subnet-${count.index + 1}"
    Environment = "production"
  }
}

data "aws_availability_zones" "available" {}


resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }

  tags = {
    Name        = "wordpress-public-route-table"
    Environment = "production"
  }
}


resource "aws_route_table_association" "public_subnet_association" {
 count          = length(var.public_subnet_cidrs)
 subnet_id      = aws_subnet.public_subnets[count.index].id
 route_table_id = aws_route_table.public_route_table.id
}


# Security Groups

# ... (Security Groups for EC2, RDS, and ELB - will be added in next iteration based on instance and database configurations)

# EC2 Instances and Autoscaling
# ... (EC2, Launch Template, ASG - details will be filled in later iterations based on OS, WordPress configuration, etc.)


# RDS Instance

# ... (RDS instance - specific engine, storage, etc. to be determined in future iterations)

# Elastic Load Balancer
# ... (ELB configuration - listener types, health checks, etc. to be defined based on application requirements)



# S3 Bucket
# ... (S3 bucket configuration, including lifecycle policies and access control)

# CloudFront Distribution
# ... (CloudFront distribution, including origin, caching behavior, and SSL certificates)

# Route 53
# ... (Route53 configuration – hosted zone and record sets based on domain details)

output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}
