terraform {
  required_providers {
    aws = {
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
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ami_id" {
  type    = string
  default = data.aws_ami.amazon_linux_2.id
}

data "aws_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}



# VPC and Networking
resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "wordpress-vpc"
    Environment = "production"
  }
}

resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name        = "wordpress-public-subnet-${count.index}"
    Environment = "production"
  }
}


resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
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
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}


# Security Groups

resource "aws_security_group" "web_server_sg" {
 name_prefix = "allow_tls"
  description = "Allow TLS inbound traffic"
 vpc_id = aws_vpc.wordpress_vpc.id


  ingress {
    description      = "TLS from VPC"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = [aws_vpc.wordpress_vpc.cidr_block]
    ipv6_cidr_blocks = [aws_vpc.wordpress_vpc.ipv6_cidr_block_association_id]

  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }


  tags = {
    Name = "wordpress-web-server-sg"
  }
}


# EC2 Instances & Autoscaling

resource "aws_launch_template" "wordpress_lt" {


  name_prefix = "wordpress-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type



  network_interfaces {
    security_groups = [aws_security_group.web_server_sg.id]
  }


  user_data = filebase64("${path.module}/wordpress_install.sh") # Placeholder script


  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "wordpress-instance"

    }
  }
}



resource "aws_autoscaling_group" "wordpress_asg" {

  name_prefix = "wordpress-asg-"
  min_size                  = 2
  max_size                  = 4


  vpc_zone_identifier = aws_subnet.public_subnets[*].id
 launch_template {
    id      = aws_launch_template.wordpress_lt.id
    version = "$latest"
  }


  tag {
    key                 = "Name"
    value               = "wordpress-asg"
    propagate_at_launch = true
  }
}


# Placeholder for other resources. These will be added in subsequent iterations based on user feedback.



