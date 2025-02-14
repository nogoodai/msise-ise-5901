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
  default     = "us-west-2"
  description = "The AWS region to deploy resources into."
}

variable "project_name" {
  type        = string
  default     = "wordpress-project"
  description = "The name of the project."
}

variable "environment" {
  type        = string
  default     = "production"
  description = "The environment name (e.g., production, development)."
}

variable "db_password" {
  type        = string
  description = "Password for the RDS database. Must be at least 8 characters long."
  sensitive   = true
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of allowed CIDR blocks for SSH access to web servers."
  default     = []
}



# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  }

}

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

resource "aws_route_table_association" "public_subnet_association_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_route_table.id
}

data "aws_availability_zones" "available" {}

resource "aws_flow_log" "main" {
 vpc_id = aws_vpc.main.id
 traffic_type = "ALL"
 log_destination_type = "s3"
 log_destination = "arn:aws:s3:::${var.project_name}-flow-logs"
 max_aggregation_interval = 600
}

resource "aws_s3_bucket" "flow_logs_bucket" {
  bucket = "${var.project_name}-flow-logs"
  acl    = "private"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
 sse_algorithm = "AES256"
      }
    }
  }

  lifecycle {
    prevent_destroy = false
  }

}



# Security Groups
resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow inbound HTTPS and SSH from specific CIDRs"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port        = 443
    to_port          = 443
    protocol        = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] # Allow HTTPS from anywhere
    description      = "Allow HTTPS traffic"
  }
  ingress {
    from_port        = 22
    to_port          = 22
    protocol        = "tcp"
    cidr_blocks      = var.allowed_cidr_blocks
    description      = "Allow SSH traffic from allowed CIDRs"

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
    description      = "Allow MySQL traffic from web servers"

  }

  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
  }
}



# EC2 Instances & Autoscaling

resource "aws_instance" "web_server" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  associate_public_ip_address = false
 monitoring = true

  user_data = <<-EOF
#!/bin/bash
sudo yum update -y
sudo yum install httpd -y
sudo systemctl enable httpd
sudo systemctl start httpd
echo "<h1>Hello from Terraform!</h1>" > /var/www/html/index.html

  EOF
  tags = {
    Name        = "${var.project_name}-web-server"
    Environment = var.environment
  }
}

data "aws_ami" "amazon_linux" {
 most_recent = true
 owners      = ["amazon"]

 filter {
   name   = "name"
   values = ["amzn2-ami-hvm-*-x86_64-gp2"]
 }
 filter {
    name   = "virtualization-type"
    values = ["hvm"]
 }
}

# RDS Instance
resource "aws_db_instance" "default" {
  allocated_storage              = 20
  storage_type                   = "gp2"
  engine                         = "mysql"
  engine_version                 = "8.0"
  instance_class                 = "db.t3.micro"
  name                           = "wordpressdb"
  username                       = "wordpressuser"
  password                       = var.db_password
  parameter_group_name           = "default.mysql8.0"
  skip_final_snapshot            = true
  vpc_security_group_ids         = [aws_security_group.rds_sg.id]
  db_subnet_group_name           = aws_db_subnet_group.default.name
  storage_encrypted              = true
  backup_retention_period        = 7
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]
  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
  }

}

resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id]

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
  }
}




# Output
output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC"
}

output "web_server_private_ip" {
 value       = aws_instance.web_server.private_ip
 description = "The private IP address of the web server"
}

output "rds_endpoint" {
 value = aws_db_instance.default.endpoint
 description = "The endpoint of the RDS instance"
}



