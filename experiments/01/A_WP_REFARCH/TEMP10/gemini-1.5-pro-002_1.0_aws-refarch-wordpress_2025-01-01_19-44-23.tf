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

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "db_instance_class" {
  type    = string
  default = "db.t2.micro"
}


resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "wordpress-vpc"
    Environment = "production"
  }
}

resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name        = "wordpress-public-subnet-${count.index + 1}"
    Environment = "production"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name        = "wordpress-private-subnet-${count.index + 1}"
    Environment = "production"
  }
}

data "aws_availability_zones" "available" {}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "wordpress-igw"
    Environment = "production"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name        = "wordpress-public-route-table"
    Environment = "production"
  }
}

resource "aws_route_table_association" "public_subnet_associations" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}


resource "aws_security_group" "web_sg" {
 name = "wordpress-web-sg"
  vpc_id = aws_vpc.wordpress_vpc.id

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


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_http_https"
  }
}


resource "aws_instance" "wordpress_instances" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = var.instance_type
  count                       = 2
  subnet_id                   = aws_subnet.public_subnets[count.index].id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  associate_public_ip_address = true
  user_data = <<EOF
#!/bin/bash
yum update -y
yum install httpd php php-mysql -y
systemctl start httpd
systemctl enable httpd
echo "<?php phpinfo(); ?>" > /var/www/html/index.php
EOF


  tags = {
    Name        = "wordpress-instance-${count.index + 1}"
    Environment = "production"

  }
}
data "aws_ami" "amazon_linux_2" {
 most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amazon-linux-2*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


resource "aws_db_instance" "default" {
  allocated_storage    = 20
  storage_type        = "gp2"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = var.db_instance_class
  name                = "wordpressdb"
  username             = "admin" # Replace with your desired username
  password             = "password123" # Replace with a strong password
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true
  db_subnet_group_name = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  tags = {
    Name = "wordpress-db"
  }
}


resource "aws_security_group" "rds_sg" {
  name = "allow_tls"

 description = "Allow TLS inbound traffic"
  vpc_id = aws_vpc.wordpress_vpc.id


  ingress {
    description      = "TLS from VPC"
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
 cidr_blocks = ["0.0.0.0/0"]


  }
}

resource "aws_db_subnet_group" "default" {

  name       = "main"
 subnet_ids = [for subnet in aws_subnet.private_subnets : subnet.id]

  tags = {
 Name = "mydbsubnetgroup"
  }
}




output "website_urls" {
  value = [for instance in aws_instance.wordpress_instances : instance.public_ip]
}


