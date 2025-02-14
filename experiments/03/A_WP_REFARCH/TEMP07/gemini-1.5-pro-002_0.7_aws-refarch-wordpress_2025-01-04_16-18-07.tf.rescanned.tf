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
  description = "The environment name (e.g., production, development)."
  default     = "production"
}

variable "db_password" {
  type        = string
  description = "Password for the RDS database. Must be strong."
  sensitive   = true
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of allowed CIDR blocks for SSH access."
  default     = ["0.0.0.0/0"] # Default is open,  replace this with a restrictive CIDR
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


resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false
  tags = {
    Name        = "${var.project_name}-public-subnet-a"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project_name}-private-subnet-a"
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

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}


data "aws_availability_zones" "available" {}

# Security Groups
resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow HTTPS inbound"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] # Open to the world for HTTPS; consider restricting
    description = "HTTPS access from anywhere" # Added description
  }

 ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "SSH access" # Added description
  }


  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"] # Added egress rule for IPv6
 description = "Allow all outbound traffic" # Added description
  }

  tags = {
    Name        = "${var.project_name}-web-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow inbound traffic from web servers"
  vpc_id      = aws_vpc.main.id

 ingress {
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
 security_groups = [aws_security_group.web_sg.id]
 description = "MySQL access from web servers" # Added description
  }

  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}


# EC2 Instances and Auto Scaling
resource "aws_instance" "web_server" {

  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
 subnet_id = aws_subnet.public_a.id
 vpc_security_group_ids = [aws_security_group.web_sg.id]
 user_data = <<EOF
#!/bin/bash
yum update -y
yum install httpd php mysql php-mysql -y
systemctl start httpd
systemctl enable httpd
echo "<h1>Hello from Terraform!</h1>" > /var/www/html/index.html
EOF
 monitoring = true
  tags = {
    Name        = "${var.project_name}-web-server"
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

# RDS Instance
resource "aws_db_instance" "default" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  name                 = "wordpress"
  username             = "admin" # Replace with your username. Use IAM auth in production
  password             = var.db_password
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true
 vpc_security_group_ids = [aws_security_group.rds_sg.id]
 db_subnet_group_name = aws_db_subnet_group.default.name
 storage_encrypted = true
 backup_retention_period = 7 # Set backup retention
 enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]
 iam_database_authentication_enabled = true


  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id]

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
    Project     = var.project_name
  }
}


# ELB (Application Load Balancer)
resource "aws_lb" "web" {

  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
 security_groups = [aws_security_group.web_sg.id]
 subnets = [aws_subnet.public_a.id]

 enable_deletion_protection = true
 drop_invalid_header_fields = true



  tags = {
    Name        = "${var.project_name}-alb"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_lb_target_group" "web" {
  name        = "${var.project_name}-target-group"
  port        = 443 # Changed to HTTPS port
  protocol    = "HTTPS" # Changed to HTTPS protocol
  vpc_id      = aws_vpc.main.id
 target_type = "instance"



  health_check {
    path                = "/"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 5
    timeout             = 5
    port = "443" # Updated health check port to 443 for HTTPS
  }

    tags = { # Added tags to the target group
    Name        = "${var.project_name}-target-group"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.web.arn
  port              = "443"
  protocol          = "HTTPS"

  ssl_policy = "ELBSecurityPolicy-TLS-1-2-Ext-2018-06" # Modern SSL policy

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}



resource "aws_lb_listener_rule" "instance_rule" {
 listener_arn = aws_lb_listener.https.arn # Updated listener ARN to HTTPS
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}


# S3 Bucket

resource "aws_s3_bucket" "static_assets" {
  bucket = "${var.project_name}-static-assets"
  acl    = "private"

  versioning {
    enabled = true
  }

  logging {
    target_bucket = "s3-log-bucket" # Ideally, a dedicated logging bucket
    target_prefix = "log/"
  }
 server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Name        = "${var.project_name}-static-assets"
    Environment = var.environment
    Project     = var.project_name
  }

}


# Outputs
output "vpc_id" {
  value       = aws_vpc.main.id
  description = "ID of the created VPC"
}

output "alb_dns_name" {
  value       = aws_lb.web.dns_name
  description = "DNS name of the Application Load Balancer"
}

output "rds_endpoint" {
  value       = aws_db_instance.default.endpoint
  description = "Endpoint of the RDS instance"
}


output "s3_bucket_arn" {
  value = aws_s3_bucket.static_assets.arn
  description = "The ARN of the S3 bucket"
}
