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

variable "project" {
  type    = string
  default = "wordpress-project"
}

variable "environment" {
  type    = string
  default = "production"
}


# VPC and Networking
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "${var.project}-vpc"
    Environment = var.environment
    Project     = var.project
  }
}


resource "aws_subnet" "public_subnet_a" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project}-public-subnet-a"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "public_subnet_b" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name        = "${var.project}-public-subnet-b"
    Environment = var.environment
    Project     = var.project
  }
}


resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "${var.project}-igw"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }

  tags = {
    Name        = "${var.project}-public-route-table"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table_association" "public_subnet_a_association" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_b_association" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_route_table.id
}

data "aws_availability_zones" "available" {}



# Security Groups

resource "aws_security_group" "wordpress_sg" {
 name        = "${var.project}-wordpress-sg"
  description = "Allow inbound traffic to WordPress instances"
  vpc_id      = aws_vpc.wordpress_vpc.id

 ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name        = "${var.project}-wordpress-sg"
    Environment = var.environment
    Project     = var.project
  }
}


# EC2 Instances and Auto Scaling

resource "aws_launch_configuration" "wordpress_lc" {

  image_id            = "ami-0c94855ba95c574c8" # Example AMI, replace with your desired AMI
  instance_type        = "t2.micro"
  security_groups      = [aws_security_group.wordpress_sg.id]


  user_data = <<-EOF
#!/bin/bash
yum update -y
yum install httpd php mysql -y
systemctl start httpd
systemctl enable httpd
echo "Hello World from $(hostname -f)" > /var/www/html/index.html
  EOF



  lifecycle {
    create_before_destroy = true
  }


}



resource "aws_autoscaling_group" "wordpress_asg" {

  name                 = "${var.project}-wordpress-asg"
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  min_size             = 1
  max_size             = 3
  vpc_zone_identifier  = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]


  health_check_grace_period = 300
  health_check_type         = "ELB"


}



# RDS Instance

resource "aws_db_instance" "wordpress_db" {

  identifier           = "${var.project}-wordpress-db"
  engine               = "mysql"
  engine_version       = "8.0" # Or latest
  instance_class       = "db.t2.micro"
  db_name              = "wordpress"
  username             = var.db_username
  password             = var.db_password
 skip_final_snapshot = true
  allocated_storage    = 20

 multi_az                 = false # For simplicity in this example, but highly recommended for production

}
variable "db_username" {
  type = string
}

variable "db_password" {
  type = string
}





output "alb_dns_name" {
 value = aws_lb.wordpress_alb.dns_name

}