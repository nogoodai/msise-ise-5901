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
  cidr_block        = "10.0.2.0/24"
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

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block        = "0.0.0.0/0"
    gateway_id         = aws_internet_gateway.gw.id
  }

  tags = {
    Name        = "${var.project_name}-public-route-table"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public_subnet_association_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_route_table.id
}

# Security Groups
resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow inbound HTTP, HTTPS and SSH"
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
    cidr_blocks = ["0.0.0.0/0"] # Replace with your source IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-web-sg"
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


resource "aws_launch_configuration" "wordpress_lc" {
  name_prefix                 = "${var.project_name}-lc-"
  image_id                    = data.aws_ami.amazon_linux.id
  instance_type               = "t2.micro"
  security_groups             = [aws_security_group.web_sg.id]
  user_data                   = "#!/bin/bash\necho \"Hello from user data\"" # Replace with your actual user data
  associate_public_ip_address = true


  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "${var.project_name}-asg"
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  min_size                  = 1
  max_size                  = 2
  vpc_zone_identifier       = [aws_subnet.public_a.id]
  health_check_grace_period = 300
  health_check_type         = "EC2"

  tag {
    key                 = "Name"
    value               = "${var.project_name}-asg-instance"
    propagate_at_launch = true
  }
}


# Load Balancer
resource "aws_elb" "wordpress_elb" {
 name = "${var.project_name}-elb"
  subnets        = [aws_subnet.public_a.id]
  security_groups = [aws_security_group.web_sg.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }


  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    target = "HTTP:80/"
    interval = 30
  }


}

resource "aws_elb_attachment" "asg_attachment" {
  elbs        = [aws_elb.wordpress_elb.id]
  instance    = aws_autoscaling_group.wordpress_asg.id
}


# RDS Instance
resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id]

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
  }
}


resource "aws_db_instance" "default" {
  allocated_storage    = 20
  db_name              = "wordpress"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class        = "db.t2.micro"
  identifier           = "${var.project_name}-db"
  username             = "admin" # Replace with your username
  password             = "password" # Replace with your password
  db_subnet_group_name = aws_db_subnet_group.default.name
  skip_final_snapshot  = true
  publicly_accessible = false


}


# S3 Bucket
resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "${var.project_name}-assets"
  acl    = "private"


}

data "aws_availability_zones" "available" {}



output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

