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
  description = "The AWS region to deploy resources in."
  default     = "us-west-2"
}

variable "project_name" {
  type        = string
  description = "The name of the project."
  default     = "wordpress-project"
}

variable "environment" {
  type        = string
  description = "The environment name (e.g., production, staging)."
  default     = "production"
}

variable "db_password" {
  type        = string
  description = "Password for the RDS database. Must be at least 8 characters."
 sensitive   = true
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of allowed CIDR blocks."
  default = ["0.0.0.0/0"]
}
variable "certificate_arn" {
 type = string
  description = "ARN of the SSL certificate for the ALB listener."
}


# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    Project     = var.project_name
  }
}


data "aws_availability_zones" "available" {}

resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "${var.project_name}-public-subnet-1"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "public_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name        = "${var.project_name}-public-subnet-2"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "${var.project_name}-private-subnet-1"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.20.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name        = "${var.project_name}-private-subnet-2"
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

resource "aws_route_table_association" "public_subnet_1_association" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_2_association" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_route_table.id
}

# Security Groups

resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow inbound HTTPS and SSH from specific CIDR blocks"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = var.allowed_cidr_blocks
    description = "HTTPS access from allowed CIDR blocks"

  }

 ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks # SSH access
    description = "SSH access from allowed CIDR blocks"
 }

 egress {
 from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    description = "All outbound traffic"

  }

  tags = {
    Name        = "${var.project_name}-web-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow inbound MySQL/Aurora from web servers"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
 security_groups = [aws_security_group.web_sg.id]
    description = "MySQL/Aurora access from web servers"

 }

 tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow inbound HTTPS for ALB"
  vpc_id      = aws_vpc.main.id

 ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = var.allowed_cidr_blocks
 description = "HTTPS access from allowed CIDR blocks"
  }

  egress {
    from_port        = 0
    to_port          = 0
 protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    description = "All outbound traffic"

 }

  tags = {
    Name        = "${var.project_name}-alb-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}


# EC2 Instances & Auto Scaling

resource "aws_launch_template" "wordpress_lt" {
 name_prefix   = "${var.project_name}-wordpress-lt-"
  image_id      = "ami-0c94855ba95c574c7" # Replace with your desired AMI
  instance_type = "t2.micro"

 network_interfaces {
    security_groups = [aws_security_group.web_sg.id]
 associate_public_ip_address = false
    subnet_id = aws_subnet.private_1.id
  }


  user_data = filebase64("./wordpress_install.sh") # Replace with your user data script

 tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-wordpress-instance"
      Environment = var.environment
      Project     = var.project_name
    }
  }
  lifecycle {
    create_before_destroy = true
  }


 tags = {
    Name = "${var.project_name}-launch-template"
    Environment = var.environment
 Project = var.project_name
  }
}


resource "aws_autoscaling_group" "wordpress_asg" {
  name                 = "${var.project_name}-wordpress-asg"
  vpc_zone_identifier  = [aws_subnet.private_1.id, aws_subnet.private_2.id]
  launch_template {
    id      = aws_launch_template.wordpress_lt.id
    version = "$Latest"
  }
  min_size         = 2
  max_size         = 4
 health_check_type = "ELB"
  target_group_arns = [aws_lb_target_group.wordpress_tg.arn]

  tag {
    key                 = "Name"
    value              = "${var.project_name}-asg"
    propagate_at_launch = true
  }
  tag {
    key                 = "Environment"
    value              = var.environment
    propagate_at_launch = true
  }
  tag {
 key                 = "Project"
    value              = var.project_name
 propagate_at_launch = true
  }
}


# RDS Instance

resource "aws_db_instance" "wordpress_db" {
 allocated_storage    = 20
  storage_type      = "gp2"
  engine            = "mysql"
 engine_version       = "8.0.32" # Replace with your desired version
  instance_class      = "db.t2.micro"
 name              = "wordpressdb"
  username             = "admin" # Replace with your desired username. Consider using IAM Authentication instead.
  password             = var.db_password
  db_subnet_group_name = aws_db_subnet_group.default.name
 vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  skip_final_snapshot   = true
  storage_encrypted     = true
  backup_retention_period = 7
 enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]
  iam_database_authentication_enabled = true


  multi_az = true
 tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_db_subnet_group" "default" {
 name       = "${var.project_name}-db-subnet-group"
 subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]

 tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Elastic Load Balancer

resource "aws_lb" "wordpress_alb" {
 name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
 drop_invalid_header_fields = true
 enable_deletion_protection = true

  tags = {
    Name        = "${var.project_name}-alb"
 Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = 443
 protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

resource "aws_lb_target_group" "wordpress_tg" {
 name     = "${var.project_name}-tg"
 port     = 80
 protocol = "HTTP"
 vpc_id   = aws_vpc.main.id

  health_check {
    path = "/"
  }

  tags = {
    Name = "${var.project_name}-target-group"
 Environment = var.environment
 Project = var.project_name
  }
}


# S3 Bucket

resource "aws_s3_bucket" "wordpress_static_assets" {
  bucket = "${var.project_name}-static-assets"
  acl    = "private"


 versioning {
    enabled = true
  }

 logging {
    target_bucket = "logging-bucket-name" # Replace with your logging bucket name
 target_prefix = "s3-logs/${var.project_name}-static-assets/"
  }
  server_side_encryption_configuration {
    rule {
 apply_server_side_encryption_by_default {
 sse_algorithm     = "AES256"
 }
    }
  }

  tags = {
    Name        = "${var.project_name}-s3-bucket"
    Environment = var.environment
    Project     = var.project_name
  }

}


# Outputs
output "alb_dns_name" {
 value       = aws_lb.wordpress_alb.dns_name
 description = "The DNS name of the application load balancer."
}

output "rds_endpoint" {
  value       = aws_db_instance.wordpress_db.endpoint
  description = "The endpoint of the RDS instance."
}
output "s3_bucket_arn" {
 value = aws_s3_bucket.wordpress_static_assets.arn
  description = "The ARN of the s3 bucket"
}

