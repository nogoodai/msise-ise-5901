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
  description = "The AWS region to deploy into."
  default     = "us-west-1"
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

variable "db_password" {
  type        = string
  description = "Password for the database.  This should be set via a secure method such as an environment variable or secrets manager."
  sensitive   = true
}

variable "db_username" {
  type        = string
  description = "Username for the database."
  default     = "admin"
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of allowed CIDR blocks for SSH access."
  default     = []
}

variable "key_name" {
  type        = string
  description = "Name of the EC2 key pair."
}

# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project_name}-public-subnet-a"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project_name}-private-subnet-a"
    Environment = var.environment
    Project     = var.project_name
  }
}

data "aws_availability_zones" "available" {}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table" "public" {
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

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

# Security Groups

resource "aws_security_group" "web_server_sg" {
  name        = "${var.project_name}-web-server-sg"
  description = "Allow HTTP, HTTPS and SSH inbound traffic"
  vpc_id      = aws_vpc.main.id


  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    description      = "Allow HTTPS from anywhere"
  }

 ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Allow SSH from allowed CIDR blocks"
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    description      = "Allow all outbound traffic"

  }

  tags = {
    Name        = "${var.project_name}-web-server-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_db_instance" "default" {
  allocated_storage               = 20
  storage_type                    = "gp2"
  engine                          = "mysql"
  engine_version                  = "8.0"
  instance_class                  = "db.t2.micro"
  name                            = "wordpress"
  username                        = var.db_username
  password                        = var.db_password
  parameter_group_name            = "default.mysql8.0"
  skip_final_snapshot             = true
  vpc_security_group_ids          = [aws_security_group.web_server_sg.id] # Allow access from web server
  db_subnet_group_name           = aws_db_subnet_group.default.name
  storage_encrypted               = true
  iam_database_authentication_enabled = true
  backup_retention_period          = 7
    enabled_cloudwatch_logs_exports    = ["audit", "error", "general", "slowquery"]

  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id]

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
    Project     = var.project_name
  }
}


# EC2 Instances and Autoscaling

resource "aws_instance" "web" {
  ami                         = data.aws_ami.latest_amazon_linux.id
  instance_type              = "t2.micro"
  key_name                   = var.key_name
  vpc_security_group_ids     = [aws_security_group.web_server_sg.id]
  subnet_id                  = aws_subnet.public_a.id
  user_data                  = <<-EOF
#!/bin/bash
yum update -y
yum install httpd php mysql php-mysql -y
systemctl start httpd
systemctl enable httpd
echo "Hello World from $(hostname -f)" > /var/www/html/index.html
  EOF
  tags = {
    Name        = "${var.project_name}-web-server"
    Environment = var.environment
    Project     = var.project_name
  }
  associate_public_ip_address = false
  monitoring                  = true
  ebs_optimized              = true

}




data "aws_ami" "latest_amazon_linux" {

  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

}



# Placeholder - Outputs will be added in the future
output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC"
}

output "rds_endpoint" {
  value       = aws_db_instance.default.endpoint
  description = "The endpoint of the RDS instance"
}

output "web_server_public_ip" {
  value       = aws_instance.web.public_ip
  description = "Public IP of the web server"

}


