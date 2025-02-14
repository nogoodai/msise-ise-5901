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
  description = "The environment name (e.g., dev, prod)."
  default     = "dev"
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

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of allowed CIDR blocks for ingress rules."
  default = ["0.0.0.0/0"]
}

variable "certificate_arn" {
 type = string
 description = "ARN of the SSL certificate."

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

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
    Project     = var.project_name
  }
}

data "aws_availability_zones" "available" {}

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

# Security Groups
resource "aws_security_group" "allow_tls" {
  name        = "${var.project_name}-allow-tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description      = "TLS from allowed CIDR blocks"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = var.allowed_cidr_blocks
    ipv6_cidr_blocks = []
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
    description      = "Allow all outbound traffic"

  }

  tags = {
    Name        = "${var.project_name}-allow-tls-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_security_group" "wordpress_sg" {
  name        = "${var.project_name}-wordpress-sg"
  description = "Allow inbound traffic"
  vpc_id      = aws_vpc.main.id

 ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks

  }
 ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks

  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }


  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
        description      = "Allow all outbound traffic"

  }

  tags = {
    Name        = "${var.project_name}-wordpress-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

# EC2 Instances and Auto Scaling
resource "aws_instance" "wordpress" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_1.id
  vpc_security_group_ids      = [aws_security_group.wordpress_sg.id]
  associate_public_ip_address = true
  user_data = <<EOF
#!/bin/bash
yum update -y
yum install httpd php mysql php-mysql -y
systemctl start httpd
systemctl enable httpd
echo "Hello World from $(hostname -f)" > /var/www/html/index.html
EOF

  tags = {
    Name        = "${var.project_name}-wordpress-instance"
    Environment = var.environment
    Project     = var.project_name
  }


  ebs_optimized = true
  monitoring = true
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
resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_db_instance" "default" {
  allocated_storage             = 20
  storage_type                 = "gp2"
  engine                       = "mysql"
  engine_version               = "8.0"
  instance_class               = "db.t2.micro"
  name                         = "wordpressdb"
  username                     = var.db_username
  password                     = var.db_password
  parameter_group_name          = "default.mysql8.0"
  db_subnet_group_name         = aws_db_subnet_group.default.name
  skip_final_snapshot          = true
  vpc_security_group_ids       = [aws_security_group.allow_tls.id]
  storage_encrypted            = true
  backup_retention_period      = 7
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]

  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Elastic Load Balancer (ALB)
resource "aws_lb" "main" {
  name                     = "${var.project_name}-lb"
  internal                 = false
  load_balancer_type        = "application"
  security_groups           = [aws_security_group.allow_tls.id]
  subnets                  = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  enable_deletion_protection = true
 drop_invalid_header_fields = true


  tags = {
    Name        = "${var.project_name}-alb"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.certificate_arn

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

resource "aws_lb_target_group" "main" {
  name        = "${var.project_name}-lb-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    path                = "/"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
  }

  tags = {
    Name        = "${var.project_name}-lb-tg"
    Environment = var.environment
    Project     = var.project_name
  }


}

resource "aws_lb_target_group_attachment" "main" {
  target_group_arn = aws_lb_target_group.main.arn
  target_id        = aws_instance.wordpress.id
  port             = 80
}

# S3 Bucket
resource "aws_s3_bucket" "static_assets" {
  bucket = "${var.project_name}-static-assets"
  acl    = "private"

  versioning {
    enabled = true
  }

  logging {
    target_bucket = "s3-bucket-logging" # Replace with your logging bucket
    target_prefix = "log/"
  }


  tags = {
    Name        = "${var.project_name}-s3"
    Environment = var.environment
    Project     = var.project_name
  }

}


# Output
output "alb_dns_name" {
  value       = aws_lb.main.dns_name
  description = "The DNS name of the ALB."
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.static_assets.bucket
  description = "The name of the S3 bucket."

}


