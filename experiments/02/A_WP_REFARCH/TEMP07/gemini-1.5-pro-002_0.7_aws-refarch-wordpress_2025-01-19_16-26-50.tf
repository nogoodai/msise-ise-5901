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
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "wordpress-vpc"
    Environment = "production"
  }
}


resource "aws_subnet" "public_subnets" {
  for_each                = toset(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = each.value
  availability_zone       = data.aws_availability_zones.available.names[index(var.public_subnet_cidrs, each.value)]
  map_public_ip_on_launch = true

  tags = {
    Name        = "wordpress-public-subnet-${index(var.public_subnet_cidrs, each.value)}"
    Environment = "production"
  }
}

resource "aws_subnet" "private_subnets" {
  for_each = toset(var.private_subnet_cidrs)
  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = each.value
  availability_zone = data.aws_availability_zones.available.names[index(var.private_subnet_cidrs, each.value)]

  tags = {
    Name        = "wordpress-private-subnet-${index(var.private_subnet_cidrs, each.value)}"
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
 for_each = toset(var.public_subnet_cidrs)
 subnet_id      = aws_subnet.public_subnets[each.value].id
 route_table_id = aws_route_table.public_route_table.id
}


resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

 ingress {
    description      = "TLS from VPC"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = [var.vpc_cidr]
    ipv6_cidr_blocks = []
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_tls"
  }
}

# Placeholder resources. Replace with actual implementation.
resource "aws_instance" "wordpress_instances" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro" # Replace with appropriate instance type

  # ... other configurations ...
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}



# ... (Other resources like RDS, ELB, ASG, S3, CloudFront, Route53) ...

output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}


