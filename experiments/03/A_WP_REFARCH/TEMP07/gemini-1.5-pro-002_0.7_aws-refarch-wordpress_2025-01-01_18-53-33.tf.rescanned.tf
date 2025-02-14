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
  type        = string
  description = "The AWS region to deploy into."
  default     = "us-west-2"
}

variable "project_name" {
  type        = string
  description = "The name of the project."
  default     = "wordpress-project"
}

variable "environment" {
  type        = string
  description = "The environment name (e.g., production, development)."
  default     = "production"
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of allowed CIDR blocks for inbound traffic."
  default = ["10.0.0.0/16"] # Example: restrict to VPC CIDR
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

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "${var.project_name}-public-subnet-a"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "private_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project_name}-private-subnet-a"
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



resource "aws_route_table_association" "public_subnet_association_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_route_table.id
}


# Security Groups
resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow inbound HTTPS and SSH. Restrict outbound."
  vpc_id      = aws_vpc.main.id


  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = var.allowed_cidr_blocks
    description      = "Allow HTTPS from allowed CIDR blocks"
  }

  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = var.allowed_cidr_blocks # Example: restrict SSH
    description      = "Allow SSH from allowed CIDR blocks"

  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"] # open egress, but monitor and restrict later. Least privilege
    description      = "Open all outbound traffic but monitor and restrict in future"
  }

  tags = {
    Name        = "${var.project_name}-web-sg"
    Environment = var.environment
    Project     = var.project_name
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
  name_prefix = "${var.project_name}-wordpress-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web_sg.id]
    subnet_id                   = aws_subnet.public_a.id

  }

  tags = {
    Name        = "${var.project_name}-wordpress-lt"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "${var.project_name}-wordpress-asg"
  launch_template {
    id      = aws_launch_template.wordpress_lt.id
    version = "$Latest"
  }
  min_size                  = 1
  max_size                  = 2
  vpc_zone_identifier       = [aws_subnet.public_a.id]
  health_check_grace_period = 300
  health_check_type         = "ELB"
 load_balancers = [aws_elb.wordpress_elb.id] # Associate with the ELB

  tags = {
    Name        = "${var.project_name}-wordpress-asg"
    Environment = var.environment
    Project     = var.project_name
  }

}



# Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "${var.project_name}-elb"
  security_groups = [aws_security_group.web_sg.id]

  subnets = [aws_subnet.public_a.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port          = 80
    lb_protocol      = "http"
  }
 access_logs { # Enable access logs
    bucket        = "my-elb-logs" # Replace with your S3 bucket
 interval = 5
    enabled = true
  }
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout            = 3
    target             = "HTTP:80/"
    interval           = 5
  }

  tags = {
    Name        = "${var.project_name}-elb"
    Environment = var.environment
    Project     = var.project_name
  }

}



data "aws_availability_zones" "available" {}


output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC."
}

output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
  description = "The DNS name of the ELB"
}
