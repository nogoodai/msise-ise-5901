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



resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "wordpress-vpc"
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


resource "aws_subnet" "public_subnets" {
  for_each = { for idx, cidr in var.public_subnet_cidrs : idx => cidr }

  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = each.value
  availability_zone       = var.availability_zones[index(var.public_subnet_cidrs, each.value)]
  map_public_ip_on_launch = true



  tags = {
    Name        = "wordpress-public-subnet-${index(var.public_subnet_cidrs, each.value)}"
    Environment = "production"
  }
}


resource "aws_subnet" "private_subnets" {
  for_each = { for idx, cidr in var.private_subnet_cidrs : idx => cidr }

  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = each.value
  availability_zone = var.availability_zones[index(var.private_subnet_cidrs, each.value)]


  tags = {
    Name        = "wordpress-private-subnet-${index(var.private_subnet_cidrs, each.value)}"
    Environment = "production"
  }
}


resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id


  tags = {
    Name        = "wordpress-public-route-table"
    Environment = "production"
  }
}


resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}


resource "aws_route_table_association" "public_subnet_association" {
 for_each = aws_subnet.public_subnets

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public_route_table.id
}



resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "wordpress-private-route-table"
    Environment = "production"
  }
}

resource "aws_route_table_association" "private_subnet_association" {
 for_each = aws_subnet.private_subnets

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_route_table.id
}


# Security Groups

resource "aws_security_group" "web_sg" {
  name        = "wordpress-web-sg"
  description = "Allow inbound HTTP/HTTPS and SSH"
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

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["YOUR_IP/32"] # Replace with your public IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "wordpress-web-sg"
    Environment = "production"
  }
}



# Placeholder resources. Replace with actual implementations.

resource "aws_instance" "wordpress_instances" {
  # ... (EC2 instance configuration)
 count = 2
  ami           = "ami-0c94855ba95c574c8" # Replace with a suitable AMI
  instance_type = "t2.micro"
 subnet_id = aws_subnet.public_subnets[0].id
 vpc_security_group_ids = [aws_security_group.web_sg.id]

  tags = {
    Name = "wordpress-instance"
  }
}


resource "aws_db_instance" "default" {

  identifier = "wordpress-db"
  engine               = "mysql"
  engine_version       = "8.0.30"
 instance_class          = "db.t3.micro"
  username              = "admin" # Replace with a strong password
  password              = "password123" # Replace with a strong password
  # allocated_storage    = 20
  # db_subnet_group_name = aws_db_subnet_group.default.name
  # publicly_accessible  = false
  skip_final_snapshot = true
  vpc_security_group_ids = [aws_security_group.web_sg.id]
}





# Output example
output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}


