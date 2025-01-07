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
  default = "development"
}


# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    Project     = var.project_name
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
    Project     = var.project_name
  }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project_name}-private-subnet-1"
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

resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_route_table.id
}


# Security Groups

resource "aws_security_group" "web_sg" {
 name        = "${var.project_name}-web-sg"
  description = "Allow inbound HTTP and HTTPS"
  vpc_id      = aws_vpc.main.id

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
    Name        = "${var.project_name}-web-sg"
    Environment = var.environment
 Project     = var.project_name
  }
}


resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
 description = "Allow inbound MySQL/Aurora"
  vpc_id      = aws_vpc.main.id

  ingress {
 from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
 security_groups = [aws_security_group.web_sg.id]

 }
  egress {
 from_port        = 0
    to_port          = 0
    protocol        = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
 tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

# EC2 Instance
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
 values = ["amzn2-ami-hvm-*-x86_64-gp2"]
 }
}


# RDS Instance

resource "aws_db_instance" "default" {
 allocated_storage    = 20
  storage_type        = "gp2"
 engine              = "mysql"
  engine_version      = "8.0"
 instance_class      = "db.t3.micro"
  name                = "wordpressdb"
  username            = "admin" # Replace with secure values
  password            = "password"  # Replace with secure values
  parameter_group_name = "default.mysql8.0"
  db_subnet_group_name = aws_db_subnet_group.default.name
 vpc_security_group_ids = [aws_security_group.rds_sg.id]
 skip_final_snapshot   = true
  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
    Project     = var.project_name
  }

}



resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-db-subnet-group"
 subnet_ids = [aws_subnet.private_1.id]

 tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
    Project     = var.project_name
  }
}

data "aws_availability_zones" "available" {}

# ... (Rest of the resources will be added in the subsequent responses due to character limits)

