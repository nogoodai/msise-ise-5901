terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type        = string
  description = "The AWS region to deploy resources into."
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

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of allowed CIDR blocks for inbound traffic."
 default = ["0.0.0.0/0"] #Restrict in production
}

variable "ssh_allowed_cidr_blocks" {
  type        = list(string)
  description = "List of allowed CIDR blocks for SSH access."
 default = ["0.0.0.0/0"] #Restrict in production
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
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "${var.project_name}-public-subnet-a"
    Environment = var.environment
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  tags = {
    Name        = "${var.project_name}-public-subnet-b"
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

resource "aws_route_table" "public" {
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

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}



data "aws_availability_zones" "available" {}

# Security Groups
resource "aws_security_group" "web_server_sg" {
 name        = "${var.project_name}-web-server-sg"
  description = "Allow inbound HTTPS and SSH from approved CIDR blocks and outbound all traffic"
  vpc_id      = aws_vpc.main.id

 ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = var.allowed_cidr_blocks
    description      = "HTTPS access from allowed CIDR blocks"

  }

  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = var.ssh_allowed_cidr_blocks
    description = "SSH access from allowed CIDR blocks"


  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
 description = "All outbound traffic"

  }



  tags = {
    Name        = "${var.project_name}-web-server-sg"
    Environment = var.environment
  }
}



# EC2 Instances

resource "aws_instance" "web_server" {
  ami                         = "ami-0c94855ba95c574c8" # Replace with hardened AMI
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.web_server_sg.id]
  associate_public_ip_address = false
  monitoring                  = true
  ebs_optimized               = true

  user_data = <<EOF
#!/bin/bash
sudo apt update
sudo apt install -y apache2 php libapache2-mod-php php-mysql
sudo systemctl start apache2
sudo echo "<html><body><h1>Hello from Terraform!</h1></body></html>" | sudo tee /var/www/html/index.html
EOF

  tags = {
    Name        = "${var.project_name}-web-server"
    Environment = var.environment
  }
}


# Outputs
output "web_server_private_ip" {
  value       = aws_instance.web_server.private_ip
  description = "Private IP address of the web server instance."
}



