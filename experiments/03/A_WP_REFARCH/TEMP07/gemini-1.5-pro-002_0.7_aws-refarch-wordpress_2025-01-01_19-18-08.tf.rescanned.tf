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
  description = "The AWS region to deploy into."
  default     = "us-west-2"
}

variable "project_name" {
  type        = string
  description = "The name of the project."
  default     = "wordpress-project"
}

variable "environment" {
  type        = string
  description = "The environment (e.g., production, development)."
  default     = "production"
}

variable "rds_username" {
  type        = string
  description = "The RDS database username."
  sensitive   = true
}


variable "rds_password" {
 type        = string
  description = "The RDS database password."
  sensitive   = true

}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of allowed CIDR blocks for web traffic."
  default     = ["0.0.0.0/0"] # Default allows all, should be restricted in production.

}

variable "ssh_allowed_cidr_blocks" {
  type        = list(string)
  description = "List of allowed CIDR blocks for SSH access."
  default = ["0.0.0.0/0"] # WARNING: Restrict SSH access to trusted IPs in production.

}



# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

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
resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow inbound HTTPS and SSH (restricted)"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = var.allowed_cidr_blocks
    description      = "Allow HTTPS from allowed CIDR blocks"
  }

  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = var.ssh_allowed_cidr_blocks
    description      = "Allow SSH from allowed CIDR blocks"

  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    description      = "Allow all outbound traffic"
  }


  tags = {
    Name        = "${var.project_name}-web-sg"
    Environment = var.environment
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow inbound MySQL/Aurora from web servers"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
    security_groups = [aws_security_group.web_sg.id]
    description      = "Allow MySQL/Aurora traffic from web servers"

  }

  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
  }
}


# EC2 Instances and Auto Scaling
resource "aws_instance" "web_server" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnet_a.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  associate_public_ip_address = true # To be removed if instance is in private subnet. Consider using a load balancer.
  monitoring                  = true
  ebs_optimized               = true

 user_data = <<EOF
#!/bin/bash
sudo yum update -y
sudo yum install httpd -y
sudo systemctl start httpd
sudo systemctl enable httpd
echo "<h1>Hello from Terraform!</h1>" > /var/www/html/index.html

EOF

  tags = {
    Name        = "${var.project_name}-web-server"
    Environment = var.environment
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


# ... (RDS, ELB, CloudFront, S3, Route53 -  Implementation below requires more variables and user data to be fully functional. These are placeholders to demonstrate the structure.)

# RDS Instance
resource "aws_db_instance" "default" {

  allocated_storage            = 20
  db_subnet_group_name        = "default" # Should be created separately.
  engine                      = "mysql"
  engine_version              = "8.0"
  instance_class               = "db.t2.micro"
  name                        = "mydb"
  username                    = var.rds_username
  password                    = var.rds_password
  parameter_group_name        = "default.mysql8.0"
  publicly_accessible          = false
  storage_encrypted           = true
  iam_database_authentication_enabled = true
  backup_retention_period               = 7
  enabled_cloudwatch_logs_exports      = ["audit", "error", "general", "slowquery"] # Example, adjust as needed


  vpc_security_group_ids = [aws_security_group.rds_sg.id]


  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
  }
  # ... other RDS configurations ...
}


# Elastic Load Balancer (ALB)
resource "aws_lb" "alb" {
 # ... ALB configurations ...
 enable_deletion_protection = true
 drop_invalid_header_fields = true
  tags = {
    Name        = "${var.project_name}-alb"
    Environment = var.environment
  }
}

# ... (CloudFront, S3, Route53 - similar structure with placeholders)



output "website_url" {
  description = "The public IP of the web server."
  value       = aws_instance.web_server.public_ip
}

output "rds_endpoint" {
  description = "The endpoint of the RDS instance."
 value = aws_db_instance.default.endpoint
}

output "vpc_id" {
  description = "The ID of the VPC."
  value = aws_vpc.main.id
}
