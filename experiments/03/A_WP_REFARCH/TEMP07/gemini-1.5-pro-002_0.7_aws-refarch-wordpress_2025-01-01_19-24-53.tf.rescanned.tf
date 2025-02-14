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
  type        = string
  default     = "us-west-2"
  description = "The AWS region to deploy into."
}

variable "project_name" {
  type        = string
  default     = "wordpress-project"
  description = "The name of the project."
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "The environment (dev, staging, prod)."
}

variable "rds_username" {
  type        = string
  description = "The RDS instance username."
  sensitive   = true
}

variable "rds_password" {
  type        = string
  description = "The RDS instance password."
  sensitive   = true

}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of allowed CIDR blocks for SSH access."
  default     = []

}

variable "ami_id" {
  type        = string
  description = "The AMI ID to use for the EC2 instance."


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

resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false
  tags = {
    Name        = "${var.project_name}-public-subnet-a"
    Environment = var.environment
  }
}

resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project_name}-private-subnet-a"
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
    Name        = "${var.project_name}-public-route-table"
    Environment = var.environment
  }
}


resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_route_table.id
}


# Security Groups
resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow inbound HTTPS and SSH from specific CIDRs and outbound all traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = var.allowed_cidr_blocks
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
    description      = "Allow all outbound traffic"

  }


  tags = {
    Name        = "${var.project_name}-web-sg"
    Environment = var.environment
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow inbound MySQL/Aurora from web server"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
    security_groups = [aws_security_group.web_sg.id]
    description      = "Allow MySQL/Aurora traffic from web server security group"

  }

  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
  }
}


# EC2 Instance
resource "aws_instance" "web_server" {
  ami                         = var.ami_id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnet_a.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  associate_public_ip_address = true
 monitoring = true
  ebs_optimized = true


  user_data = <<EOF
#!/bin/bash
sudo yum update -y
sudo amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2
sudo yum install -y httpd mariadb-server
sudo systemctl start httpd
sudo systemctl enable httpd
sudo systemctl start mariadb
sudo systemctl enable mariadb
EOF


  tags = {
    Name        = "${var.project_name}-web-server"
    Environment = var.environment
  }
}




# RDS Instance
resource "aws_db_instance" "default" {

  allocated_storage                = 20
  storage_type                     = "gp2"
  engine                           = "mysql"
  engine_version                   = "8.0"
  instance_class                   = "db.t2.micro"
  name                             = "wordpressdb"
  username                         = var.rds_username
  password                         = var.rds_password
  parameter_group_name             = "default.mysql8.0"
  vpc_security_group_ids            = [aws_security_group.rds_sg.id]
  skip_final_snapshot               = true
  db_subnet_group_name             = aws_db_subnet_group.default.name
  storage_encrypted                = true
  iam_database_authentication_enabled = true
  backup_retention_period           = 12
  enabled_cloudwatch_logs_exports    = ["audit", "error", "general", "slowquery"]



  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
  }
}


resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_a.id]

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
  }
}


# Outputs

output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC"
}

output "web_server_public_ip" {
  value       = aws_instance.web_server.public_ip
  description = "Public IP address of the web server"
}

output "rds_endpoint" {
  value       = aws_db_instance.default.endpoint
  description = "The endpoint of the RDS instance"
}


