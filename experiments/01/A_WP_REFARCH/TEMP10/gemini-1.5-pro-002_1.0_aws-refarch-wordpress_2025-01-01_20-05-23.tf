terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
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

variable "name_prefix" {
  type    = string
  default = "wordpress-prod"
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


resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "${var.name_prefix}-vpc"
    Environment = "production"
  }
}

resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "${var.name_prefix}-public-subnet-${count.index}"
    Environment = "production"
  }
}

resource "aws_subnet" "private" {
 count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "${var.name_prefix}-private-subnet-${count.index}"
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

resource "aws_route_table" "public" {
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



resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}


resource "aws_security_group" "web" {
  name        = "${var.name_prefix}-web-sg"
  description = "Allow inbound HTTP and HTTPS"
  vpc_id      = aws_vpc.main.id

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
    Name        = "${var.name_prefix}-web-sg"
    Environment = "production"
  }
}


resource "aws_db_subnet_group" "default" {

  name       = "${var.name_prefix}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "${var.name_prefix}-db-subnet-group"
    Environment = "production"
  }
}

resource "aws_db_instance" "default" {

  identifier              = "${var.name_prefix}-db"
  allocated_storage       = 20
  storage_encrypted        = true
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro"
 username               = "admin" # Replace with your desired username
  password               = random_password.password.result # Replace with a secure password
  db_subnet_group_name   = aws_db_subnet_group.default.name
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.web.id] # Allow access from web servers

  tags = {
    Name        = "${var.name_prefix}-rds"
    Environment = "production"
  }
}

resource "random_password" "password" {
  length = 16
  special = true
  override_special = "!#$%&()*+,-./:;<=>?@[]^_{|}~"
}



# Placeholder - Replace with your actual instance configuration
resource "aws_instance" "web_servers" {

  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.micro" # Replace with your desired instance type
  key_name      = "your-keypair-name" # Replace with your key pair name

 # subnet_id     = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.web.id]

  user_data = <<EOF
#!/bin/bash
yum update -y
yum install httpd php mysql -y
systemctl start httpd
systemctl enable httpd

echo "<?php phpinfo(); ?>" > /var/www/html/index.php

EOF



  tags = {
    Name        = "${var.name_prefix}-ec2"
    Environment = "production"
  }

}

data "aws_ami" "amazon_linux_2" {
 most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}


# Placeholder for S3 Bucket
resource "aws_s3_bucket" "static_assets" {
  bucket = "${var.name_prefix}-static-assets"

  tags = {
    Name = "${var.name_prefix}-s3-bucket"
    Environment = "production"

  }
}





output "website_endpoint" {
 value = aws_instance.web_servers.public_ip # Placeholder for now
}

output "rds_endpoint" {
 value = aws_db_instance.default.address
}

