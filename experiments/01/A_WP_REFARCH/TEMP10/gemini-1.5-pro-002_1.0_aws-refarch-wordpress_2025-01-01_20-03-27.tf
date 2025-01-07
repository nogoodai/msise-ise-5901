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

variable "availability_zones" {
  type    = list(string)
  default = ["us-west-2a", "us-west-2b"]
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ami_id" {
  type    = string
  default = "ami-0c94855ba95c574c8" # Amazon Linux 2 AMI (HVM), SSD Volume Type
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
  cidr_block        = var.public_subnet_cidrs[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "wordpress-public-subnet-${count.index}"
    Environment = "production"

  }
}


resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  cidr_block        = var.private_subnet_cidrs[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "wordpress-private-subnet-${count.index}"
    Environment = "production"
  }
}

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

resource "aws_route_table_association" "public_subnet_association" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}


resource "aws_security_group" "web_sg" {
  name        = "wordpress-web-sg"
  description = "Allow inbound HTTP, HTTPS and SSH"
  vpc_id      = aws_vpc.wordpress_vpc.id

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
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name        = "wordpress-web-sg"
    Environment = "production"
  }
}



resource "aws_instance" "web_server" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_subnets[0].id # Place in the first public subnet
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  associate_public_ip_address = true

    user_data = <<-EOF
#!/bin/bash
sudo yum update -y
sudo yum install httpd php php-mysql -y
sudo systemctl start httpd
sudo systemctl enable httpd
sudo echo "<?php phpinfo(); ?>" > /var/www/html/index.php
  EOF



  tags = {
    Name        = "wordpress-web-server"
    Environment = "production"
  }
}



output "web_server_public_ip" {
 value = aws_instance.web_server.public_ip
}


