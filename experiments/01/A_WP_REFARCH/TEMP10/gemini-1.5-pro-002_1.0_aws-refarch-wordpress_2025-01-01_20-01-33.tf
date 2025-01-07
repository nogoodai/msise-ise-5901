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
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

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
 map_public_ip_on_launch = true
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
 map_public_ip_on_launch = true
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



data "aws_availability_zones" "available" {}

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


# Security Groups

resource "aws_security_group" "allow_tls" {
  name        = "${var.project_name}-allow-tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.main.id

 ingress {
    description      = "TLS from VPC"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]

  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }


  tags = {
    Name        = "${var.project_name}-allow-tls"
    Environment = var.environment
    Project     = var.project_name
  }
}




# EC2 Instances & Autoscaling

resource "aws_launch_template" "wordpress_lt" {


  name_prefix   = "${var.project_name}-wordpress-lt-"
  image_id      = "ami-0c94855ba95c574c8" # Replace with your desired AMI
  instance_type = "t2.micro"

  network_interfaces {
    associate_public_ip_address = true
    security_groups              = [aws_security_group.allow_tls.id]

  }


  user_data = <<-EOF
#!/bin/bash
sudo yum update -y
sudo amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2
sudo yum install -y httpd mariadb-server
sudo systemctl start httpd
sudo systemctl enable httpd
sudo systemctl start mariadb
sudo systemctl enable mariadb
EOF


  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-wordpress-instance"
      Environment = var.environment
      Project     = var.project_name
    }
  }

 lifecycle {
    create_before_destroy = true
  }
}


resource "aws_autoscaling_group" "wordpress_asg" {

  launch_template {

    id      = aws_launch_template.wordpress_lt.id
    version = "$Latest"
  }



  min_size                  = 2
  max_size                  = 4

  vpc_zone_identifier = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  health_check_grace_period = 300
 health_check_type           = "EC2"



  tags = {
    Name        = "${var.project_name}-wordpress-asg"
    Environment = var.environment
    Project     = var.project_name

  }
}





# Load Balancer

resource "aws_lb" "wordpress_lb" {


  name               = "${var.project_name}-lb"
 internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_tls.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  tags = {
    Name        = "${var.project_name}-alb"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_lb_listener" "front_end" {

  load_balancer_arn = aws_lb.wordpress_lb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:iam::123456789012:server-certificate/test_cert_rab3wuqwgja25ct3n4jdjlds4a" # Replace with your certificate ARN



  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}



resource "aws_lb_target_group" "wordpress_tg" {

  name        = "${var.project_name}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

 health_check {
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
  }
}


resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.wordpress_asg.name
  lb_target_group_arn    = aws_lb_target_group.wordpress_tg.arn
}

# Outputs
output "load_balancer_dns_name" {
  value = aws_lb.wordpress_lb.dns_name
}



