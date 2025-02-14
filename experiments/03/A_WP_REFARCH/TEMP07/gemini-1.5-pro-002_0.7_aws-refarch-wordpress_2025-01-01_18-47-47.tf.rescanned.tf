terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Use a more flexible version constraint
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type        = string
  default     = "us-west-2"
  description = "The AWS region to deploy the resources in."
}

variable "project_name" {
  type        = string
  default     = "wordpress-project"
  description = "The name of the project."
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "The environment (e.g., dev, prod)."
}


variable "db_username" {
  type        = string
  description = "The database username."
  sensitive   = true

}

variable "db_password" {
  type        = string
  description = "The database password."
  sensitive   = true
}

variable "key_name" {
  type        = string
  description = "The name of the EC2 key pair."
  sensitive   = true
}


variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of allowed CIDR blocks for SSH access to the bastion host."
  default     = [] # Default to empty list for security
}



variable "certificate_arn" {
  type        = string
  description = "The ARN of the SSL certificate for the ALB listener."

}

# VPC
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

# Subnets
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
 map_public_ip_on_launch = false # Turned off for security

  tags = {
    Name        = "${var.project_name}-public-subnet-1"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "${var.project_name}-private-subnet-1"
    Environment = var.environment
    Project     = var.project_name
  }
}


data "aws_availability_zones" "available" {}

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
resource "aws_route_table" "public_route_table" {
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



resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_route_table.id
}


# Security Groups

resource "aws_security_group" "web_sg" {
 name               = "${var.project_name}-web-sg"
  description        = "Allow HTTPS inbound"
  vpc_id            = aws_vpc.main.id


  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    description = "Allow HTTPS traffic from anywhere" # Added description
  }

 ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = var.allowed_cidr_blocks
    description = "Allow SSH traffic from allowed CIDR blocks" # Added description

  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"  # Added description
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
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
 description = "Allow MySQL traffic from web servers" # Added description
  }

  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

# EC2 Instance (Bastion - Optional, but recommended for accessing private resources)
resource "aws_instance" "bastion" {
  ami                    = "ami-0c94855ba95c574c8" # Replace with your desired AMI
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.web_sg.id] #  Use the web security group for SSH access
 key_name               = var.key_name
  ebs_optimized         = true
  monitoring            = true


  tags = {
    Name = "${var.project_name}-bastion"
    Environment = var.environment
    Project     = var.project_name
  }
}


# RDS Instance
resource "aws_db_instance" "default" {
  allocated_storage                = 20
  storage_type                     = "gp2"
  engine                           = "mysql"
  engine_version                   = "8.0"
  instance_class                   = "db.t2.micro"
  name                             = "wordpressdb"
  username                         = var.db_username
  password                         = var.db_password
  parameter_group_name             = "default.mysql8.0"
  skip_final_snapshot              = true
  vpc_security_group_ids           = [aws_security_group.rds_sg.id]
  db_subnet_group_name             = aws_db_subnet_group.main.name
 storage_encrypted                = true
  backup_retention_period          = 7
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports      = ["audit", "error", "general", "slowquery"]


  tags = {
    Name = "${var.project_name}-rds"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_1.id]

  tags = {
    Name = "${var.project_name}-db-subnet-group"
    Environment = var.environment
    Project     = var.project_name
  }

}



# EC2 Instances for WordPress (using Launch Template and Autoscaling Group)
resource "aws_launch_template" "wordpress_lt" {
  name_prefix = "${var.project_name}-wordpress-lt-"

  image_id      = "ami-0c94855ba95c574c8" # Replace with your desired AMI
  instance_type = "t2.micro"
  network_interfaces {
 security_groups             = [aws_security_group.web_sg.id]
    associate_public_ip_address = true # Required for ALB access
    subnet_id                   = aws_subnet.public_1.id
  }
  user_data = <<-EOF
#!/bin/bash
    sudo yum update -y
    sudo yum install httpd php php-mysql -y
    sudo systemctl start httpd
    sudo systemctl enable httpd
    sudo echo "<?php phpinfo(); ?>" > /var/www/html/index.php
  EOF



  tags = {
    Name = "${var.project_name}-wordpress-lt"
    Environment = var.environment
    Project     = var.project_name
  }

}


resource "aws_autoscaling_group" "wordpress_asg" {
  name_prefix          = "${var.project_name}-wordpress-asg-"
  min_size            = 1
  max_size            = 2
  vpc_zone_identifier = [aws_subnet.public_1.id]
 launch_template {
    id      = aws_launch_template.wordpress_lt.id
    version = "$Latest"
  }
  tag {
    key                 = "Name"
    value                = "${var.project_name}-webserver"
    propagate_at_launch = true
  }


  tags = {
    Name = "${var.project_name}-asg"
    Environment = var.environment
    Project     = var.project_name
  }

}


# Elastic Load Balancer
resource "aws_lb" "wordpress_alb" {
  name                       = "${var.project_name}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.web_sg.id]
  subnets                    = [aws_subnet.public_1.id]
 enable_deletion_protection  = true
  drop_invalid_header_fields = true

  tags = {
    Name = "${var.project_name}-alb"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lb_listener" "http" {
 load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "redirect"
    redirect {
      port        = 443
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

}


resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
 certificate_arn = var.certificate_arn
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}


resource "aws_lb_target_group" "wordpress_tg" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id


  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${var.project_name}-tg"
    Environment = var.environment
    Project     = var.project_name
  }
}



resource "aws_autoscaling_attachment" "asg_attachment_to_tg" {
  autoscaling_group_name = aws_autoscaling_group.wordpress_asg.name
  lb_target_group_arn    = aws_lb_target_group.wordpress_tg.arn
}



# S3 Bucket for static assets (optional)

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "${var.project_name}-assets"
  acl    = "private"
 versioning {
    enabled = true
  }
 logging {
    target_bucket = "your_logging_bucket_name" # Replace with your logging bucket name
    target_prefix = "log/"
  }


  tags = {
    Name = "${var.project_name}-s3-bucket"
    Environment = var.environment
    Project     = var.project_name
  }
}




output "alb_dns_name" {
  value       = aws_lb.wordpress_alb.dns_name
  description = "The DNS name of the Application Load Balancer."
}

output "rds_endpoint" {
  value       = aws_db_instance.default.address
  description = "The endpoint of the RDS instance."
}


