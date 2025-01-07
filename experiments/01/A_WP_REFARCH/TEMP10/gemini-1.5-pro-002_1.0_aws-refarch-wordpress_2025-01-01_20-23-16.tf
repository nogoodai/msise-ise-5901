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
  default = "production"
}


# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "public_subnet_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.region}a"
  tags = {
    Name        = "${var.project_name}-public-subnet-a"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "public_subnet_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.region}b"
  tags = {
    Name        = "${var.project_name}-public-subnet-b"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
    Project     = var.project_name
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
    Project     = var.project_name
  }
}


resource "aws_route_table_association" "public_subnet_a_association" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_b_association" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_route_table.id
}



# Security Groups

resource "aws_security_group" "web_sg" {
 name        = "${var.project_name}-web-sg"
  description = "Allow inbound HTTP/HTTPS"
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
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-web-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}


# EC2 Instances & Autoscaling

resource "aws_launch_template" "wordpress_lt" {
  name = "${var.project_name}-wordpress-lt"


  image_id = "ami-0c94855ba95c574c8" # Example AMI
 instance_type = "t2.micro"
 network_interfaces {
    security_groups = [aws_security_group.web_sg.id]
    associate_public_ip_address = true
 }

 user_data = filebase64("user_data.sh") # Replace with actual user data

  tags = {
    Name        = "${var.project_name}-wordpress-lt"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  name                 = "${var.project_name}-wordpress-asg"
 launch_template {
    id      = aws_launch_template.wordpress_lt.id
    version = "$Latest"
  }
 min_size                  = 1
  max_size                  = 3
 vpc_zone_identifier = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]

  tag {
    key                 = "Name"
    value              = "${var.project_name}-wordpress-asg"
 propagate_at_launch = true
  }
  tag {
 key                 = "Environment"
 value              = var.environment
 propagate_at_launch = true
 }
  tag {
    key                 = "Project"
 value              = var.project_name
    propagate_at_launch = true
  }

}



# Placeholder for user_data.sh - create this file with WordPress installation script
# user_data.sh
# #!/bin/bash
# # Install WordPress, etc


output "asg_name" {
 value = aws_autoscaling_group.wordpress_asg.name
}




# Output for VPC ID
output "vpc_id" {
  value = aws_vpc.main.id
}



