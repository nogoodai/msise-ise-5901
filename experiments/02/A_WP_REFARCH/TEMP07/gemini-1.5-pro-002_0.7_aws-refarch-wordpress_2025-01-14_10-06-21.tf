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
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name = "WordPressVPC-IGW"
  }
}


resource "aws_subnet" "public_subnets" {
  for_each = {
    for i, cidr in var.public_subnet_cidrs : i => cidr
  }

  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = each.value
  availability_zone = data.aws_availability_zones.available.names[each.key]
  tags = {
    Name = "WordPressVPC-PublicSubnet-${each.key}"
  }

}

resource "aws_subnet" "private_subnets" {
  for_each = {
    for i, cidr in var.private_subnet_cidrs : i => cidr
  }

  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = each.value
  availability_zone = data.aws_availability_zones.available.names[each.key]
 tags = {
    Name = "WordPressVPC-PrivateSubnet-${each.key}"
  }
}



data "aws_availability_zones" "available" {}


resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "WordPressVPC-PublicRouteTable"
  }
}


resource "aws_route_table_association" "public_subnet_association" {
 for_each = aws_subnet.public_subnets
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public_route_table.id
}


resource "aws_security_group" "web_sg" {
  name        = "web_sg"
  description = "Allow inbound HTTP and HTTPS"
  vpc_id      = aws_vpc.wordpress_vpc.id

 ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }


  tags = {
    Name = "web_sg"
  }
}


# Placeholder for more complex resources and best practices.
# These placeholders will be replaced with complete, production-ready
# code in a future iteration, including:

# - Bastion host setup
# - EFS configuration and alarms
# - Elasticache configuration
# - Public ALB configuration
# - RDS instance, security groups, parameter groups
# - CloudFront distribution and security
# - Route 53 records
# - Monitoring dashboards and metrics
# - Master files with parameters and mappings
# - Web server configuration with launch configuration and user data
# - Auto Scaling Group
# - S3 bucket for static assets


output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}



