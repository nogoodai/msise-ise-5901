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
  cidr_block        = "10.0.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project_name}-private-subnet-a"
    Environment = var.environment
  }
}


resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
  }
}

resource "aws_route_table" "public" {
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


resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}


# Security Groups

resource "aws_security_group" "web_server_sg" {
 name        = "${var.project_name}-web-server-sg"
  description = "Allow HTTP, HTTPS and SSH inbound traffic"
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

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Replace with your IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-web-server-sg"
    Environment = var.environment
  }
}


# EC2 Instances and Auto Scaling

data "aws_ami" "amazon_linux" {
 most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_launch_template" "wordpress_lt" {
  name_prefix   = "${var.project_name}-wordpress-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  network_interfaces {
    security_groups = [aws_security_group.web_server_sg.id]
    associate_public_ip_address = true
    subnet_id                   = aws_subnet.public_a.id
  }

  user_data = filebase64("user_data.sh") # Create this file with your WordPress installation script

  lifecycle {
    create_before_destroy = true
  }
}


# Placeholder for user_data.sh - Create this file with your WordPress installation script
# Example:
# #!/bin/bash
# yum update -y
# yum install httpd php mysql -y
# systemctl start httpd
# systemctl enable httpd


resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "${var.project_name}-wordpress-asg"
  min_size                  = 1
  max_size                  = 3
  desired_capacity          = 1
  vpc_zone_identifier       = [aws_subnet.public_a.id]
 launch_template {
    id      = aws_launch_template.wordpress_lt.id
    version = "$Latest"
  }
  tag {
    key                 = "Name"
    value               = "${var.project_name}-wordpress-instance"
    propagate_at_launch = true
  }
}


# Load Balancer

resource "aws_elb" "wordpress_elb" {
 name               = "${var.project_name}-elb"
  subnets            = [aws_subnet.public_a.id]
  security_groups    = [aws_security_group.web_server_sg.id]
  internal           = false
  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 30
  }

  tags = {
    Name        = "${var.project_name}-elb"
    Environment = var.environment
  }
}


resource "aws_elb_attachment" "wordpress_elb_attachment" {
  elbs        = [aws_elb.wordpress_elb.id]
  instances   = aws_autoscaling_group.wordpress_asg.instances
}


# Output

output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

data "aws_availability_zones" "available" {}


# Placeholder for RDS, S3, CloudFront, and Route53.  These would be added here following similar patterns as above.


