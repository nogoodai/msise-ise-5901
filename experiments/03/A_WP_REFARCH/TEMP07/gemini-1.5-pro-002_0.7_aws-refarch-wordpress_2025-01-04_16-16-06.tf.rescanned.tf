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
  description = "The environment (e.g., production, development)."
  default     = "production"
}

variable "db_password" {
  type        = string
  description = "The password for the RDS instance.  This should be changed to a secure, randomly generated password using a secrets management tool."
  sensitive   = true
 default = "Password123!"
}

variable "allowed_cidr_blocks" {
  type = list(string)
  description = "List of allowed CIDR blocks"
  default = ["0.0.0.0/0"] # Default allows all traffic for testing purposes. In production this value should be changed to the specific IP or range of IPs allowed to access the EC2 instance.
}

variable "ssh_allowed_cidr_blocks" {
  type = list(string)
 description = "List of allowed CIDR blocks for SSH access"
  default = ["0.0.0.0/0"] # Default allows SSH access from all IPs for testing purposes. In production this value should be changed to a list containing only the allowed IP address or CIDR block for SSH access.
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

resource "aws_route_table_association" "public_subnet_association_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_route_table.id
}


# Security Groups

resource "aws_security_group" "web_server_sg" {
 name        = "${var.project_name}-web-server-sg"
  description = "Allow inbound HTTP, HTTPS and SSH"
  vpc_id      = aws_vpc.main.id

 ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Allow HTTP traffic"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Allow HTTPS traffic"
  }

 ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidr_blocks
    description = "Allow SSH traffic"
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${var.project_name}-web-server-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}


# EC2 Instances and Auto Scaling

resource "aws_instance" "web_server" {
  ami           = "ami-0c94855ba95c574c7" # Replace with your desired AMI
  instance_type = "t2.micro"
  subnet_id = aws_subnet.public_a.id # Replace with your subnet ID
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  user_data = file("${path.module}/wordpress_install.sh") # Replace with your script
 monitoring = true


  tags = {
    Name        = "${var.project_name}-web-server"
    Environment = var.environment
    Project     = var.project_name
  }


  lifecycle {
    create_before_destroy = true
  }
}

# Placeholder for wordpress_install.sh - This MUST be created separately
# #!/bin/bash
# sudo apt update
# sudo apt install -y apache2 php libapache2-mod-php mysql-client php-mysql wget unzip
# cd /var/www/html
# wget https://wordpress.org/latest.zip
# unzip latest.zip
# # ... rest of wordpress installation



# RDS Instance

resource "aws_db_instance" "default" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t2.micro"
  identifier           = "${var.project_name}-db"
  username             = "admin" # Replace with your username.  This should be changed to use IAM authentication.
  password             = var.db_password
  db_subnet_group_name = aws_db_subnet_group.default.name
  skip_final_snapshot  = true
    vpc_security_group_ids = [aws_security_group.web_server_sg.id] # Temporarily allow access from web server for testing.  Update with dedicated DB SG
  storage_encrypted = true
  backup_retention_period = 7
  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"] # Example log types
  iam_database_authentication_enabled = true

  tags = {
    Name        = "${var.project_name}-db"
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



# Placeholder for remaining components.  These will need to be implemented based on the full requirements
# ... (Elastic Load Balancer, Auto Scaling Group, CloudFront, S3, Route 53) ...



output "ec2_public_ip" {
  value       = aws_instance.web_server.public_ip
  description = "Public IP address of the EC2 instance"
}

output "rds_endpoint" {
 value = aws_db_instance.default.address
 description = "Endpoint address of the RDS instance"
}



