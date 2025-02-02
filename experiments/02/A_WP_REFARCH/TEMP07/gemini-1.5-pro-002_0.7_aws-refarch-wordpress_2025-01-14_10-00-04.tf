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
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  }
}


resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags = {
    Name        = "${var.project_name}-public-subnet-1"
    Environment = var.environment
  }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "${var.project_name}-private-subnet-1"
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

resource "aws_route_table" "public_route_table" {
 vpc_id = aws_vpc.main.id

 route {
   cidr_block = "0.0.0.0/0"
   gateway_id = aws_internet_gateway.gw.id
 }

 tags = {
   Name = "${var.project_name}-public-route-table"
   Environment = var.environment
 }
}


resource "aws_route_table_association" "public_subnet_association" {
 subnet_id      = aws_subnet.public_1.id
 route_table_id = aws_route_table.public_route_table.id
}


# Security Groups

resource "aws_security_group" "allow_tls" {
  name        = "${var.project_name}-allow-tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.main.id

 ingress {
   description      = "TLS from VPC"
   from_port        = 443
   to_port          = 443
   protocol         = "tcp"
   cidr_blocks      = ["10.0.0.0/16"] # VPC CIDR
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
    Name        = "${var.project_name}-allow-tls-sg"
    Environment = var.environment
  }
}



# Placeholder resources - replace with actual implementations

resource "aws_instance" "wordpress_instance" {
  ami           = "ami-0c94855ba95c574c8" # Replace with appropriate AMI
  instance_type = "t2.micro"
  subnet_id = aws_subnet.public_1.id # Ensure correct subnet placement
  vpc_security_group_ids = [aws_security_group.allow_tls.id]
  tags = {
    Name        = "${var.project_name}-wordpress-instance"
    Environment = var.environment
  }
}

resource "aws_db_instance" "default" {
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "8.0.34" # Example, adjust as needed
  instance_class         = "db.t2.micro"
  name                   = "wordpressdb"
  username               = "admin" # Example username, DO NOT USE IN PRODUCTION
  password               = "password123" # Example password, DO NOT USE IN PRODUCTION; use secrets management
  parameter_group_name   = "default.mysql8.0"
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.allow_tls.id]

  tags = {
    Name        = "${var.project_name}-rds-instance"
    Environment = var.environment
  }
}


# Outputs

output "vpc_id" {
  value = aws_vpc.main.id
}


