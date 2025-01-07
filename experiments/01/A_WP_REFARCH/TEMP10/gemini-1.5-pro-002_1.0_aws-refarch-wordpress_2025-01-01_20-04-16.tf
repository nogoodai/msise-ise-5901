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

resource "aws_security_group" "allow_tls" {
  name        = "${var.project_name}-allow-tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.main.id

 ingress {
    description      = "TLS from VPC"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["10.0.0.0/16"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name        = "${var.project_name}-security-group-allow-tls"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_security_group" "wordpress_instance" {
  name        = "${var.project_name}-wordpress-instance-sg"
  description = "Allow inbound HTTP and SSH"
  vpc_id      = aws_vpc.main.id


  ingress {
    from_port   = 80
    to_port     = 80
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
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }


  tags = {
    Name        = "${var.project_name}-security-group-wordpress"
    Environment = var.environment
    Project     = var.project_name
  }
}




# EC2 Instances and Autoscaling

resource "aws_instance" "wordpress_server" {

  count = 2

  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t2.micro" # Change to desired instance type
  subnet_id                   = aws_subnet.public_1.id # Change to private subnet for production
  vpc_security_group_ids      = [aws_security_group.wordpress_instance.id]
  associate_public_ip_address = true # Set to false if instances are in private subnet
  user_data                   = file("user_data.sh") # Replace with your user data script

  tags = {
    Name        = "${var.project_name}-wordpress-instance-${count.index}"
    Environment = var.environment
    Project     = var.project_name
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




resource "aws_elb" "wordpress_elb" {

 lifecycle { create_before_destroy = true }

  name               = "${var.project_name}-elb"
  subnets           = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  security_groups    = [aws_security_group.allow_tls.id]
  internal           = false
  cross_zone_load_balancing = true

  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port             = 80
    lb_protocol         = "http"
  }


 health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    target = "HTTP:80/"
    interval = 30
 }



  tags = {
    Name        = "${var.project_name}-elb"
    Environment = var.environment
    Project     = var.project_name
  }

}



resource "aws_elb_attachment" "elb_attachment" {

 count = length(aws_instance.wordpress_server)


  instance = aws_instance.wordpress_server[count.index].id
  elb      = aws_elb.wordpress_elb.id
}



# RDS Instance

resource "aws_db_instance" "default" {
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "8.0" # Choose a supported version
  instance_class         = "db.t2.micro" # Adjust to fit your needs
  name                   = "wordpress" # The database name
  username               = "wordpress_user" # Replace with your preferred username
  password               = random_password.password.result  # Replace with your preferred password
  parameter_group_name   = "default.mysql8.0"
  vpc_security_group_ids = [aws_security_group.allow_tls.id] # Security Group allowing connection from your EC2 instances
  skip_final_snapshot    = true # Optional: Prevent final snapshot during destruction

  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
    Project     = var.project_name
  }
}




resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "!#$%&()*+,-./:;<=>?@[]^_{|}~"
}


#  S3 Bucket



resource "aws_s3_bucket" "wordpress_assets" {

 force_destroy = true

  bucket = "${var.project_name}-s3-bucket"
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

output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}


output "rds_endpoint" {
  value = aws_db_instance.default.endpoint
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.wordpress_assets.arn
}

