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
  default = "us-east-1"
}

variable "name_prefix" {
  type    = string
  default = "wordpress"
}

# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "${var.name_prefix}-vpc"
    Environment = "production"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "${var.name_prefix}-igw"
    Environment = "production"
  }
}


resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags = {
    Name        = "${var.name_prefix}-public-subnet-a"
    Environment = "production"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.name_prefix}-private-subnet-a"
    Environment = "production"
  }
}


data "aws_availability_zones" "available" {}


resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name        = "${var.name_prefix}-public-route-table"
    Environment = "production"
  }
}


resource "aws_route_table_association" "public_subnet_association_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_route_table.id
}




# Security Groups

resource "aws_security_group" "web_sg" {
 name = "${var.name_prefix}-web-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

    ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Restrict in production
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.name_prefix}-web-sg"
    Environment = "production"
  }
}

resource "aws_security_group" "rds_sg" {
 name = "${var.name_prefix}-rds-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
 security_groups = [aws_security_group.web_sg.id]

  }
  tags = {
    Name = "${var.name_prefix}-rds-sg"
        Environment = "production"
  }
}




# EC2 and Autoscaling

resource "aws_instance" "web_server" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t2.micro" # Consider larger size for production
  subnet_id                   = aws_subnet.private_a.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  associate_public_ip_address = false
  user_data = <<EOF
#!/bin/bash
yum update -y
yum install -y httpd php mysql
systemctl start httpd
systemctl enable httpd
echo "Hello World from $(hostname -f)" > /var/www/html/index.php
EOF

  tags = {
    Name = "${var.name_prefix}-web-server"
        Environment = "production"
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name    = "name"
    values = ["amzn2-ami-hvm*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}



# RDS


resource "aws_db_subnet_group" "default" {
  name       = "${var.name_prefix}-db-subnet-group"
 subnet_ids = [aws_subnet.private_a.id]

  tags = {
    Name        = "${var.name_prefix}-db-subnet-group"
    Environment = "production"
  }
}


resource "aws_db_instance" "default" {
  allocated_storage = 20
  storage_type = "gp2"
  engine            = "mysql"
  engine_version    = "8.0" # Or latest supported version
  instance_class    = "db.t3.micro" # Consider a larger instance class for production
  db_name           = "wordpress"
 username          = "wordpress_user"
  password          = "StrongPassword123!" # Replace with secure password management
  db_subnet_group_name = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot = true
    delete_automated_backups = true
  publicly_accessible = false

  tags = {
    Name = "${var.name_prefix}-rds"
        Environment = "production"
  }
}


# Placeholder for S3, CloudFront, Route53, and Load Balancer

# Outputs

output "vpc_id" {
  value = aws_vpc.main.id
}

output "rds_endpoint" {
 value = aws_db_instance.default.endpoint
}

output "web_server_public_ip" {
 value = aws_instance.web_server.public_ip
}

