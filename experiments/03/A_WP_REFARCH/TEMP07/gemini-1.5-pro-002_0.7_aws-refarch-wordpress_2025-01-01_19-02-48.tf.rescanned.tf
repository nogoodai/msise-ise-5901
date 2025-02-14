terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider aws {
  region = var.aws_region
}

variable "aws_region" {
  type        = string
  description = "The AWS region to deploy resources in."
  default     = "us-west-2"
}

variable "project_name" {
  type        = string
  description = "The name of the project."
  default     = "wordpress-project"
}

variable "environment" {
  type        = string
  description = "The environment name (e.g., production, development)."
  default     = "production"
}

variable "db_password" {
  type        = string
  description = "Password for the RDS database. Must be at least 8 characters and include uppercase, lowercase, numbers, and symbols."
  sensitive   = true
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of CIDR blocks allowed to access web servers."
  default     = ["10.0.0.0/16"]
}



# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  }
}

data "aws_availability_zones" "available" {}

resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project_name}-public-subnet-a"
    Environment = var.environment
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
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

resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_route_table.id
}



# Security Groups
resource "aws_security_group" "web_sg" {
 name        = "${var.project_name}-web-sg"
  description = "Allow inbound traffic from allowed CIDR blocks"
  vpc_id      = aws_vpc.main.id


  ingress {
    from_port        = 443
    to_port          = 443
    protocol        = "tcp"
    cidr_blocks      = var.allowed_cidr_blocks
    description      = "Allow HTTPS traffic from allowed CIDR blocks"

  }

 egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"


  }

  tags = {
    Name        = "${var.project_name}-web-sg"
    Environment = var.environment
  }
}


resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow inbound traffic from web servers"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port        = 3306
    to_port          = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
    description      = "Allow MySQL traffic from web security group"

  }
  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
  }
}




# EC2 Instances
resource "aws_instance" "web_server" {
  ami                         = "ami-0c94855ba95c574c8" # Replace with appropriate AMI
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  associate_public_ip_address = false
 monitoring = true
  ebs_optimized = true



  user_data = <<-EOF
#!/bin/bash
sudo yum update -y
sudo yum install httpd -y
sudo systemctl start httpd
sudo systemctl enable httpd
echo "Hello World from $(hostname -f)" > /var/www/html/index.html
  EOF

  tags = {
    Name        = "${var.project_name}-web-server"
    Environment = var.environment
  }
}

# RDS Instance
resource "aws_db_instance" "default" {
  allocated_storage              = 10
  db_name                        = "wordpress"
  engine                         = "mysql"
  engine_version                 = "8.0" # Or latest supported version
  instance_class                 = "db.t2.micro"
  identifier                     = "${var.project_name}-rds"
  username                       = "admin"
  password                       = var.db_password
  vpc_security_group_ids         = [aws_security_group.rds_sg.id]
  skip_final_snapshot             = true
  storage_encrypted              = true
  iam_database_authentication_enabled = true
  backup_retention_period        = 7
  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]

  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
  }
}


# Output
output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC"
}

output "rds_endpoint" {
  value       = aws_db_instance.default.address
  description = "The endpoint of the RDS instance"
}

output "web_server_private_ip" {
  value       = aws_instance.web_server.private_ip
  description = "The private IP address of the web server"
}



