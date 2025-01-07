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
  }
}

resource "aws_subnet" "public_subnet_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project_name}-public-subnet-a"
    Environment = var.environment
  }
}

resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project_name}-private-subnet-a"
    Environment = var.environment
  }

}

data "aws_availability_zones" "available" {}


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
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name        = "${var.project_name}-public-route-table"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public_subnet_association_a" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_route_table.id
}



# Security Groups

resource "aws_security_group" "web_server_sg" {
 name = "${var.project_name}-web-server-sg"
  description = "Allow HTTP, HTTPS and SSH inbound traffic"
 vpc_id = aws_vpc.main.id

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
    Name = "${var.project_name}-web-sg"
  }

}

resource "aws_security_group" "rds_sg" {
  name = "${var.project_name}-rds-sg"
  description = "Allow inbound traffic from web servers"
  vpc_id = aws_vpc.main.id


  ingress {
    from_port = 3306
 to_port = 3306
 protocol = "tcp"
 security_groups = [aws_security_group.web_server_sg.id]
  }
 tags = {
    Name = "${var.project_name}-rds-sg"
  }
}




# EC2 Instances & Autoscaling

resource "aws_instance" "wordpress_instance" {
  ami           = data.aws_ami.amazon_linux.id # Replace with desired AMI
  instance_type = "t2.micro"
  subnet_id = aws_subnet.public_subnet_a.id
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  user_data = file("user_data.sh") # Replace with actual user data script

  tags = {
    Name        = "${var.project_name}-ec2-instance"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
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

# RDS Instance

resource "aws_db_instance" "default" {
 allocated_storage    = 20
  storage_type        = "gp2"
  engine              = "mysql"
  engine_version      = "8.0"
  instance_class      = "db.t2.micro"
  name                = "wordpressdb"
  username            = "admin"
 password           = "password123" # Replace with a strong password
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
 db_subnet_group_name = aws_db_subnet_group.default.name
}

resource "aws_db_subnet_group" "default" {
  name       = "main"
  subnet_ids = [aws_subnet.private_subnet_a.id]
  tags = {
    Name = "My db subnet group"
  }
}




# Load Balancer

resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_server_sg.id] # Security group for the ALB
 subnets = [aws_subnet.public_subnet_a.id]

  tags = {
 Name        = "${var.project_name}-alb"
    Environment = var.environment
  }
}


# Output



output "alb_dns_name" {
 value = aws_lb.main.dns_name
}




