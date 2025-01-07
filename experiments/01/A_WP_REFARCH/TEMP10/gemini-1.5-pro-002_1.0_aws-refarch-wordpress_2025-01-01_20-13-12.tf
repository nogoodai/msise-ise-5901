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
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  tags = {
    Name        = "${var.project_name}-public-subnet-a"
    Environment = var.environment
  }
}

resource "aws_subnet" "private_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.region}a"
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
   cidr_block = "0.0.0.0/0"
   gateway_id = aws_internet_gateway.gw.id
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
resource "aws_security_group" "web_server_sg" {
  name        = "${var.project_name}-web-server-sg"
  description = "Allow HTTP, HTTPS and SSH inbound"
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

  ingress {
    description = "SSH"
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
    Name        = "${var.project_name}-web-server-sg"
    Environment = var.environment
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow inbound traffic from web servers"
  vpc_id      = aws_vpc.main.id

 ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
  }
  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
  }
}



# EC2 Instances and Auto Scaling

resource "aws_instance" "web_server" {
  ami                         = data.aws_ami.amazon_linux.id # Replace with your desired AMI
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_a.id # Should reside in public subnet to be accessible by ALB
  vpc_security_group_ids      = [aws_security_group.web_server_sg.id]
  associate_public_ip_address = true
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

  tags = {
    Name        = "${var.project_name}-web-server"
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
  allocated_storage     = 20
  storage_type          = "gp2"
  engine                = "mysql"
  engine_version        = "8.0" # or latest
  instance_class        = "db.t2.micro"
  name                  = "wordpress" # Your database name
  username              = "admin"  # Replace with your username
  password              = "password123" # Replace with a strong password
  parameter_group_name  = "default.mysql8.0" # Adjust if needed
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot   = true
  db_subnet_group_name = aws_db_subnet_group.default.name

  tags = {
    Name = "${var.project_name}-rds"
        Environment = var.environment
  }
}



resource "aws_db_subnet_group" "default" {

  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id] # Add more subnets for HA

  tags = {
        Name = "${var.project_name}-db-subnet-group"
        Environment = var.environment
  }
}




# Elastic Load Balancer


resource "aws_elb" "wordpress_elb" {
  name               = "${var.project_name}-elb"
  subnets           = [aws_subnet.public_a.id]
  security_groups    = [aws_security_group.web_server_sg.id]
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
 }
}


# Attach EC2 instances to ELB -  Replace with Autoscaling group instances later
resource "aws_elb_attachment" "web" {
  instance_port = 80
  lb_port          = 80
  elb             = aws_elb.wordpress_elb.id
  instance        = aws_instance.web_server.id
}





# S3 Bucket for Static Assets
resource "aws_s3_bucket" "static_assets" {
  bucket = "${var.project_name}-static-assets"
  acl    = "private"


 website {
    index_document = "index.html"
    error_document = "error.html"

  }
 tags = {
        Name = "${var.project_name}-s3-bucket"
        Environment = var.environment
  }
}


# CloudFront Distribution (Basic - requires more configuration for production)


# Route53 (requires domain information)



output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "rds_endpoint" {
  value = aws_db_instance.default.endpoint
}



