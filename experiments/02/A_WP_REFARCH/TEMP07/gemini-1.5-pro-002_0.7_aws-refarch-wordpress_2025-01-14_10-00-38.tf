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
  default = "db.t3.micro"
}


resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "wordpress-vpc"
  }
}

resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  cidr_block        = var.public_subnet_cidrs[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "wordpress-public-subnet-${count.index}"
  }
}


resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  cidr_block        = var.private_subnet_cidrs[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  availability_zone = data.aws_availability_zones.available.names[count.index + length(var.public_subnet_cidrs)] # Offset for private subnets
  tags = {
    Name = "wordpress-private-subnet-${count.index}"
  }
}

data "aws_availability_zones" "available" {}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "wordpress-igw"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "wordpress-public-route-table"
  }
}


resource "aws_route_table_association" "public_subnet_association" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}


resource "aws_security_group" "web_sg" {
 name = "wordpress-web-sg"
  description = "Allow inbound HTTP, HTTPS and SSH"
  vpc_id = aws_vpc.wordpress_vpc.id

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
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Replace with your source IP
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name = "wordpress-web-sg"
  }
}

resource "aws_instance" "web_server" {
  ami = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  # Replace with your key pair name
  key_name = "your_key_pair" 

  subnet_id = aws_subnet.public_subnets[0].id # Deploy to the first public subnet
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  user_data = <<-EOF
#!/bin/bash
yum update -y
yum install httpd php mysql php-mysql -y
systemctl start httpd
systemctl enable httpd
echo "<?php phpinfo(); ?>" > /var/www/html/index.php
  EOF


  tags = {
    Name = "wordpress-web-server"
  }
}



data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}




# Placeholder resources - replace with actual implementation following security best practices
resource "aws_db_instance" "default" {
  allocated_storage = 20
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = var.db_instance_class
  # ... other configurations ...
  skip_final_snapshot = true

  db_subnet_group_name = aws_db_subnet_group.default.name

  tags = {
    Name = "wordpress-db"
  }

}

resource "aws_db_subnet_group" "default" {


  subnet_ids = aws_subnet.private_subnets[*].id

  tags = {
    Name = "wordpress-db-subnet-group"
  }
}


# Placeholder resources - replace with actual implementation following security best practices
resource "aws_s3_bucket" "default" {


  # Ensure bucket is private and follow S3 security best practices
  # ...

  tags = {
    Name = "wordpress-s3-bucket"
  }
}




output "website_url" {
 value = aws_instance.web_server.public_ip # Replace with load balancer URL when implemented
}

