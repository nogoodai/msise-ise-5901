terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Use a more flexible version constraint
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type        = string
  default     = "us-west-2"
  description = "The AWS region to deploy the resources in."
}

variable "project_name" {
  type        = string
  default     = "wordpress-project"
  description = "The name of the project."
}

variable "environment" {
  type        = string
  default     = "production"
  description = "The environment name (e.g., production, development)."
}

variable "allowed_cidr_blocks" {
  type = list(string)
  description = "List of CIDR blocks allowed to access the resources."
  default = ["1.2.3.4/32"] # Example: Replace with your actual CIDR block(s)
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

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]


  tags = {
    Name        = "${var.project_name}-public-subnet-1"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  tags = {
    Name        = "${var.project_name}-public-subnet-2"
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

resource "aws_route_table" "public" {
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

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

data "aws_availability_zones" "available" {}

# Security Groups
resource "aws_security_group" "web_server_sg" {
  name        = "${var.project_name}-web-server-sg"
  description = "Allow HTTPS and SSH inbound"
  vpc_id      = aws_vpc.main.id

  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = var.allowed_cidr_blocks


  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${var.project_name}-web-server-security-group"
    Environment = var.environment
    Project     = var.project_name
  }
}


# EC2 Instances and Autoscaling
resource "aws_launch_template" "wordpress_lt" {
  name_prefix   = "${var.project_name}-wordpress-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"


  network_interfaces {
    security_groups = [aws_security_group.web_server_sg.id]
    associate_public_ip_address = true
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.project_name}-launch-template"
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

  min_size             = 2
  max_size             = 4
  vpc_zone_identifier  = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  health_check_type    = "EC2"
  health_check_grace_period = 300
  target_group_arns = [aws_lb_target_group.wordpress_tg.arn]

  tag {
    key                 = "Name"
    value               = "${var.project_name}-web-server-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }
}


data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}




# Load Balancer
resource "aws_lb" "wordpress_lb" {
  name               = "${var.project_name}-wordpress-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_server_sg.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  drop_invalid_header_fields = true
  enable_deletion_protection = true

  tags = {
    Name        = "${var.project_name}-load-balancer"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.wordpress_lb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01" # Enforce TLS 1.2 or higher
  certificate_arn = "arn:aws:iam::123456789012:server-certificate/test_cert" # Replace with ACM Certificate ARN

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}


resource "aws_lb_target_group" "wordpress_tg" {
  name     = "${var.project_name}-wordpress-tg"
  port     = 443 # HTTPS port
  protocol = "HTTPS"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTPS" # Health checks over HTTPS
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
 tags = {
    Name        = "${var.project_name}-target-group"
    Environment = var.environment
    Project     = var.project_name
  }
}


# Outputs
output "lb_dns_name" {
  value       = aws_lb.wordpress_lb.dns_name
  description = "The DNS name of the load balancer."
}

output "lb_arn" {
  value = aws_lb.wordpress_lb.arn
  description = "The ARN of the load balancer."
}

