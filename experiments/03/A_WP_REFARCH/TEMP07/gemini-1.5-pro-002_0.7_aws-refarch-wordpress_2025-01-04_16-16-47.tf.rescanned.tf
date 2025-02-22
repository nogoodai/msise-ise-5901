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
  description = "The AWS region to deploy the resources in."
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
  description = "List of allowed CIDR blocks for SSH access to web servers."
  default = ["1.2.3.4/32"] # Example default - should be replaced with appropriate CIDR.
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
  description = "Allow inbound HTTPS and SSH from specific CIDRs, and all outbound traffic."
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port        = 443
    to_port          = 443
    protocol        = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] # Open to the world for HTTPS
    description = "HTTPS access from anywhere"
  }

 ingress {
    from_port   = 22
    to_port     = 22
    protocol   = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "SSH access from allowed CIDRs"

  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol        = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name        = "${var.project_name}-web-server-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}




# EC2 Instances and Auto Scaling
resource "aws_launch_template" "wordpress_lt" {


  name_prefix   = "${var.project_name}-wordpress-lt-"
  image_id      = "ami-0c94855ba95c574c8" # Replace with your desired AMI
  instance_type = "t2.micro"

  network_interfaces {
    security_groups = [aws_security_group.web_server_sg.id]
 associate_public_ip_address = true
  }
  user_data = <<EOF
#!/bin/bash
sudo yum update -y
sudo yum install httpd php mysql php-mysql -y
sudo systemctl start httpd
sudo systemctl enable httpd
sudo echo "<?php phpinfo(); ?>" > /var/www/html/index.php
EOF



  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.project_name}-wordpress-lt"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "${var.project_name}-wordpress-asg"
  min_size                  = 2
  max_size                  = 4
  desired_capacity          = 2
  vpc_zone_identifier       = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  health_check_type         = "EC2" # Ensure instance health checks are used
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
resource "aws_lb" "wordpress_lb" {
  name                    = "${var.project_name}-wordpress-lb"
  internal                = false
  load_balancer_type    = "application"
  security_groups         = [aws_security_group.web_server_sg.id]
  subnets                 = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  drop_invalid_header_fields = true
 enable_deletion_protection = true


  tags = {
    Name        = "${var.project_name}-wordpress-lb"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.wordpress_lb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08" # A more secure default. Consider a custom policy for optimal security.
 certificate_arn = "arn:aws:iam::123456789012:server-certificate/my-server-cert" # Placeholder. Replace with your certificate ARN.

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

resource "aws_lb_target_group" "wordpress_tg" {
  name        = "${var.project_name}-wordpress-tg"
  port        = 443 # Match the listener port
  protocol    = "HTTPS" # Match the listener protocol
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    path                = "/"
    protocol            = "HTTPS" # Match target group protocol
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }
  tags = {
    Name        = "${var.project_name}-wordpress-tg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.wordpress_asg.name
  lb_target_group_arn     = aws_lb_target_group.wordpress_tg.arn
}


output "lb_dns_name" {
  value       = aws_lb.wordpress_lb.dns_name
  description = "The DNS name of the load balancer."
}



# Placeholder for RDS, S3, CloudFront, and Route53 -  Implementation would follow similar structure with variables and best practices.
