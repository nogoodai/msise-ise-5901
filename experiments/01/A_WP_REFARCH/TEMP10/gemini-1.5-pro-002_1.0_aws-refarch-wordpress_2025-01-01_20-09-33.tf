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
  default = "dev"
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

resource "aws_route_table_association" "public_subnet_association_a" {
 subnet_id      = aws_subnet.public_a.id
 route_table_id = aws_route_table.public_route_table.id
}


# Security Groups

resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow inbound HTTP, HTTPS, and SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
  }
  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
  }
}


# EC2 Instances & Auto Scaling

resource "aws_instance" "web_server" {
  ami               = "ami-0c94855ba95c574c7" # Example AMI - Replace with appropriate AMI ID
  instance_type = "t2.micro"
  subnet_id = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
    user_data = <<-EOF
#!/bin/bash
sudo yum update -y
sudo yum install httpd -y
sudo systemctl enable httpd
sudo systemctl start httpd
sudo echo "<h1>Hello from Terraform!</h1>" > /var/www/html/index.html
  EOF

 tags = {
   Name        = "${var.project_name}-web-server"
   Environment = var.environment
 }
}

# RDS Instance

resource "aws_db_instance" "default" {
  allocated_storage    = 20
  db_name              = "wordpress"
  engine               = "mysql"
  engine_version       = "8.0.32"
  instance_class       = "db.t2.micro"
  identifier = "${var.project_name}-rds"
  username             = "admin" # Replace with your desired username
  password             = "password" # Replace with your strong password

  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true

  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment

  }
}




# S3 Bucket
resource "aws_s3_bucket" "static_assets" {
  bucket = "${var.project_name}-static-assets"


  tags = {
    Name        = "${var.project_name}-s3-bucket"
    Environment = var.environment
  }
}


# Outputs

output "vpc_id" {
  value = aws_vpc.main.id
}

output "rds_endpoint" {
  value = aws_db_instance.default.address
}

output "s3_bucket_name" {
  value = aws_s3_bucket.static_assets.bucket

}

