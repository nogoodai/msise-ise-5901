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
  type        = string
  description = "The AWS region to deploy the resources in."
  default     = "us-west-2"
}

variable "project_name" {
  type        = string
  description = "The name of the project."
  default     = "wordpress-project"
}

variable "environment" {
  type        = string
  description = "The environment name (e.g., dev, prod)."
  default     = "dev"
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of allowed CIDR blocks for inbound traffic."
  default     = ["10.0.0.0/16"] # Example private network
}


# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
 map_public_ip_on_launch = false

  tags = {
    Name        = "${var.project_name}-public-subnet-a"
    Environment = var.environment
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.region}a"

  tags = {
    Name        = "${var.project_name}-private-subnet-a"
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
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
 }
}

resource "aws_route_table_association" "public_subnet_association_a" {
 subnet_id      = aws_subnet.public_a.id
 route_table_id = aws_route_table.public_route_table.id
}

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
   description = "Allow HTTPS from allowed CIDR blocks"
 }

 ingress {
   from_port        = 22
   to_port          = 22
   protocol         = "tcp"
   cidr_blocks = ["172.16.0.0/16"] # Example restricted CIDR
   description = "Allow SSH from a restricted CIDR"


 }

 egress {
   from_port        = 0
   to_port          = 0
   protocol         = "-1"
   cidr_blocks      = ["0.0.0.0/0"]
   description = "Allow all outbound traffic"
 }


  tags = {
    Name        = "${var.project_name}-web-sg"
    Environment = var.environment
  }
}


# EC2 Instances
resource "aws_instance" "web" {
  ami           = "ami-0c94855ba95c574c7" # Replace with desired AMI
  instance_type = "t2.micro"
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
 monitoring = true
  ebs_optimized = true


  user_data = <<-EOF
    #!/bin/bash
    echo "Hello, World!" > index.html
    nohup busybox httpd -f -p 80 &
  EOF

  tags = {
    Name        = "${var.project_name}-web-instance"
    Environment = var.environment
  }
}



# Outputs
output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC."
}

output "web_sg_id" {
  value       = aws_security_group.web_sg.id
  description = "The ID of the web security group."
}

output "web_instance_public_ip" {
  value = aws_instance.web.public_ip
  description = "Public IP address of the web instance."
}
