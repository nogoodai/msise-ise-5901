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
  map_public_ip_on_launch = true
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

resource "aws_route_table_association" "public_subnet_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_route_table.id
}


# Security Groups

resource "aws_security_group" "web_sg" {
 name        = "${var.project_name}-web-sg"
  description = "Allow inbound HTTP and HTTPS"
  vpc_id      = aws_vpc.main.id

 ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
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
 vpc_id = aws_vpc.main.id

 ingress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
 security_groups = [aws_security_group.web_sg.id]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
    Environment = var.environment
  }
}

# EC2 Instances

resource "aws_instance" "web" {
  ami           = "ami-009d68f77a182881b" # Replace with appropriate AMI
 instance_type = "t2.micro"
  subnet_id = aws_subnet.public_a.id
 vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = <<-EOF
#!/bin/bash
yum update -y
yum install -y httpd php mysql
service httpd start
chkconfig httpd on
echo "Hello World from $(hostname -f)" > /var/www/html/index.html
  EOF

  tags = {
    Name = "${var.project_name}-web-server"
    Environment = var.environment
  }
}


# RDS Instance

resource "aws_db_instance" "default" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "8.0" # Or latest version
  instance_class       = "db.t2.micro"
  name                 = "wordpress"
  username             = "admin" # Replace with secure credentials
  password             = "password123" # Replace with secure credentials
  parameter_group_name = "default.mysql8.0" # Update if needed
  skip_final_snapshot  = true
 vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.default.name

  tags = {
        Name = "${var.project_name}-rds"
        Environment = var.environment
  }
}

resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id]

  tags = {
        Name = "${var.project_name}-db-subnet-group"
        Environment = var.environment
  }

}



# Outputs

output "vpc_id" {
  value = aws_vpc.main.id
}

output "web_server_public_ip" {
 value = aws_instance.web.public_ip
}


