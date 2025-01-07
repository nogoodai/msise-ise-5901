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

variable "environment" {
  type    = string
  default = "dev"
}

variable "project" {
  type    = string
  default = "wordpress"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-west-2a", "us-west-2b"]
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

# VPC and Networking
resource "aws_vpc" "wordpress-vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "wordpress-vpc"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "public-subnet-1" {
  vpc_id            = aws_vpc.wordpress-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = var.availability_zones[0]
  tags = {
    Name        = "public-subnet-1"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "public-subnet-2" {
  vpc_id            = aws_vpc.wordpress-vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = var.availability_zones[1]
  tags = {
    Name        = "public-subnet-2"
    Environment = var.environment
    Project     = var.project
  }
}


resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.wordpress-vpc.id
  tags = {
    Name        = "internet-gateway"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table" "public-route-table" {
  vpc_id = aws_vpc.wordpress-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name        = "public-route-table"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table_association" "public-subnet-1-association" {
  subnet_id      = aws_subnet.public-subnet-1.id
  route_table_id = aws_route_table.public-route-table.id
}

resource "aws_route_table_association" "public-subnet-2-association" {
  subnet_id      = aws_subnet.public-subnet-2.id
  route_table_id = aws_route_table.public-route-table.id
}


# Security Groups

resource "aws_security_group" "web_sg" {
  name        = "web_sg"
  description = "Allow inbound traffic on port 80 and 443"
  vpc_id      = aws_vpc.wordpress-vpc.id

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
    Name        = "web_sg"
    Environment = var.environment
    Project     = var.project
  }
}

# EC2 Instances and Auto Scaling

resource "aws_instance" "wordpress_instance" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public-subnet-1.id # Example: Place in public subnet for demonstration
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  user_data = <<-EOF
#!/bin/bash
    yum update -y
    yum install httpd php mysql -y
    systemctl start httpd
    systemctl enable httpd
    echo "<h1>Hello World from $(hostname -f)</h1>" > /var/www/html/index.html
  EOF


  tags = {
    Name        = "wordpress_instance"
    Environment = var.environment
    Project     = var.project
  }
}


data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

}



output "instance_public_ip" {
  value = aws_instance.wordpress_instance.public_ip
}

