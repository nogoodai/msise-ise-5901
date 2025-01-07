terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
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


# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Subnets
resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.names[0]
  tags = {
    Name        = "${var.project_name}-public-subnet-1"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "public_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.names[1]
  tags = {
    Name        = "${var.project_name}-public-subnet-2"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.101.0/24"
  availability_zone = data.aws_availability_zones.names[0]
  tags = {
    Name        = "${var.project_name}-private-subnet-1"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.102.0/24"
  availability_zone = data.aws_availability_zones.names[1]
  tags = {
    Name        = "${var.project_name}-private-subnet-2"
    Environment = var.environment
    Project     = var.project_name
  }
}


data "aws_availability_zones" {}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Route Tables
resource "aws_route_table" "public" {
 vpc_id = aws_vpc.main.id
 route {
   cidr_block        = "0.0.0.0/0"
   gateway_id         = aws_internet_gateway.gw.id
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

resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow HTTP and HTTPS inbound"
  vpc_id      = aws_vpc.main.id

 ingress {
   description = "HTTP"
   from_port   = 80
   to_port     = 80
   protocol    = "tcp"
   cidr_blocks = ["0.0.0.0/0"]
 }

 ingress {
   description = "HTTPS"
   from_port   = 443
   to_port     = 443
   protocol    = "tcp"
   cidr_blocks = ["0.0.0.0/0"]
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
    Project     = var.project_name
  }
}


# EC2 Instances & Autoscaling

resource "aws_launch_template" "web_server" {
  name = "${var.project_name}-web-launch-template"
  image_id = "ami-0c94855ba95c574c8" # Example AMI. Replace with your desired AMI.
  instance_type = "t2.micro"
 network_interfaces {
    security_groups = [aws_security_group.web_sg.id]
    associate_public_ip_address = true # For instances in public subnets
 }

 user_data = <<EOF
 #! /bin/bash
 sudo yum update -y
 sudo yum install -y httpd php mysql
 sudo systemctl start httpd
 sudo systemctl enable httpd
 echo "<html><body><h1>Hello from Terraform!</h1></body></html>" > /var/www/html/index.html

 EOF


 lifecycle {
   create_before_destroy = true
 }
}

resource "aws_autoscaling_group" "web_asg" {
  name_prefix = "${var.project_name}-web-asg-"
  min_size = 2
  max_size = 4
  desired_capacity = 2

 launch_template {
    id      = aws_launch_template.web_server.id
    version = "$Latest"
 }


 vpc_zone_identifier = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  tags = {
    Name        = "${var.project_name}-web-asg"
    Environment = var.environment
    Project     = var.project_name
  }
}




# Load Balancer

resource "aws_lb" "web_lb" {

 name               = "${var.project_name}-web-lb"
 internal           = false
 load_balancer_type = "application"
 security_groups    = [aws_security_group.web_sg.id]
 subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]

}


resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web_lb.arn
  port              = "80"
  protocol          = "HTTP"


  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}


resource "aws_lb_target_group" "web_tg" {
  name        = "${var.project_name}-web-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"


  health_check {
    path = "/"
  }
}



resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.web_asg.name
  lb_target_group_arn    = aws_lb_target_group.web_tg.arn
}





# RDS Instance

resource "aws_db_subnet_group" "private_subnet_group" {
  name       = "${var.project_name}-private-subnet-group"
 subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]


  tags = {
    Name        = "${var.project_name}-private-subnet-group"

    Environment = var.environment
    Project     = var.project_name
  }

}

resource "aws_db_instance" "default" {

  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "8.0.28" # Example. Use a supported version.
  instance_class       = "db.t3.micro"
  db_name              = "wordpress"
  username             = "admin" # Example.  Don't use default usernames in production.
  password             = random_password.rds_password.result
  parameter_group_name = "default.mysql8.0" # Example. Consider custom parameter groups.
  skip_final_snapshot  = true
  publicly_accessible = false
 db_subnet_group_name = aws_db_subnet_group.private_subnet_group.id
 multi_az              = true # Enable for high availability


  vpc_security_group_ids = [aws_security_group.web_sg.id]


  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
    Project     = var.project_name
  }

}

resource "random_password" "rds_password" {
  length = 16
  special = true
}


# S3 Bucket

resource "aws_s3_bucket" "static_assets" {

  bucket = "${var.project_name}-static-assets"
  acl    = "private"


  tags = {
    Name        = "${var.project_name}-s3-bucket"
    Environment = var.environment
    Project     = var.project_name
  }
}




# Outputs

output "vpc_id" {
  value = aws_vpc.main.id
}

output "lb_dns_name" {

  value = aws_lb.web_lb.dns_name
}

output "rds_endpoint" {

  value = aws_db_instance.default.address
}

output "s3_bucket_arn" {
 value = aws_s3_bucket.static_assets.arn
}



