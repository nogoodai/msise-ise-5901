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
  default = "dev"
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
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project_name}-public-subnet-1"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "public_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
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

resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow HTTP and SSH inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

 ingress {
    description      = "HTTPS"
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
    Name        = "${var.project_name}-web-security-group"
    Environment = var.environment
    Project     = var.project_name
  }
}



# EC2 Instances and Auto Scaling

resource "aws_launch_configuration" "wordpress_lc" {
 name_prefix = "${var.project_name}-lc-"

  image_id = "ami-0c94855ba95c574c8" # Example AMI, replace with your desired AMI
  instance_type = "t2.micro"

  security_groups = [aws_security_group.web_sg.id]


  user_data = <<-EOF
#!/bin/bash
yum update -y
yum install httpd php mysql php-mysql -y
systemctl start httpd
systemctl enable httpd
echo "<h1>Hello World from $(hostname -f)</h1>" > /var/www/html/index.html
  EOF




 lifecycle {
    create_before_destroy = true
 }
}


resource "aws_autoscaling_group" "wordpress_asg" {


  launch_configuration = aws_launch_configuration.wordpress_lc.name

  min_size             = 2
  max_size             = 4
  vpc_zone_identifier  = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  health_check_type    = "EC2"


  tag {
    key                 = "Name"
    value              = "${var.project_name}-asg"
    propagate_at_launch = true
  }


}


# Load Balancer


resource "aws_lb" "wordpress_lb" {

  name               = "${var.project_name}-lb"


  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
 subnets = [aws_subnet.public_1.id, aws_subnet.public_2.id]



}

resource "aws_lb_target_group" "wordpress_tg" {
  name        = "${var.project_name}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id


  health_check {
    path                = "/"
  }


}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.wordpress_lb.arn
  port              = "80"
  protocol          = "HTTP"



  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.wordpress_asg.name
  lb_target_group_arn    = aws_lb_target_group.wordpress_tg.arn
}


# Outputs

output "lb_dns_name" {
  value = aws_lb.wordpress_lb.dns_name
}



