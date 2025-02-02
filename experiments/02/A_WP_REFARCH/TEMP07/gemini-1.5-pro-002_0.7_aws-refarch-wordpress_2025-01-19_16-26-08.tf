terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}


# VPC and Networking
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "wordpress-vpc"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name = "wordpress-igw"
  }
}


resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "wordpress-public-subnet-${count.index + 1}"
  }

}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index + length(var.public_subnet_cidrs)]
  tags = {
    Name = "wordpress-private-subnet-${count.index + 1}"
  }
}



resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }


  tags = {
    Name = "wordpress-public-route-table"
  }
}


resource "aws_route_table_association" "public_subnet_association" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}


data "aws_availability_zones" "available" {}

# Security Groups

resource "aws_security_group" "web_sg" {
 name = "wordpress-web-sg"
  vpc_id = aws_vpc.wordpress_vpc.id

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
    cidr_blocks = ["0.0.0.0/0"] # Restrict in production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name = "wordpress-web-sg"
  }
}



resource "aws_security_group" "rds_sg" {
  name = "wordpress-rds-sg"
  vpc_id = aws_vpc.wordpress_vpc.id


 ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
 security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress-rds-sg"
  }
}



# EC2 Instances and Autoscaling

resource "aws_launch_template" "wordpress_lt" {
  name_prefix            = "wordpress-lt-"
  image_id               = "ami-0c94855ba95c574c8" # Replace with desired AMI
  instance_type          = var.instance_type


  network_interfaces {
    security_groups = [aws_security_group.web_sg.id]
 associate_public_ip_address = true
  }

 user_data = filebase64("user_data.sh") # Create user_data.sh

}

resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  min_size                  = 2
  max_size                  = 4
  vpc_zone_identifier       = aws_subnet.public_subnets[*].id
 launch_template {
    id      = aws_launch_template.wordpress_lt.id
    version = "$Latest"
  }



  tag {
    key                 = "Name"
    value               = "wordpress-instance"
    propagate_at_launch = true
  }
}



# RDS Instance


resource "aws_db_instance" "default" {
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = var.db_instance_class
  name                   = "wordpress"
  username               = "admin" # Change and store securely
  password               = "password" # Change and store securely
  parameter_group_name   = "default.mysql8.0"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true
  db_subnet_group_name  = aws_db_subnet_group.default.name
 multi_az = true


}

resource "aws_db_subnet_group" "default" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private_subnets[*].id


}


# Placeholder for S3 and CloudFront (Adapt as needed)
resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${random_id.bucket_id.hex}"
  acl    = "private"


}


resource "random_id" "bucket_id" {
  byte_length = 8
}

# Placeholder for Route53 (Adapt as needed)


output "rds_endpoint" {
 value = aws_db_instance.default.endpoint
}


