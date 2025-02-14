terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Relaxed version constraint for flexibility
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type        = string
  description = "The AWS region to deploy the resources in."
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

variable "rds_username" {
  type        = string
  description = "The username for the RDS instance."
  default     = "admin"
}

variable "rds_password" {
 type        = string
  description = "The password for the RDS instance. This should be a secure, randomly generated password."
 sensitive   = true
}


variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of allowed CIDR blocks for SSH access."
 default     = ["0.0.0.0/0"] # Default to allow all, user should restrict

}

variable "ami_id" {
  type = string
  description = "AMI id for EC2."
  default = "ami-0c94855ba95c574c8"
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


data "aws_availability_zones" "available" {}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

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

resource "aws_route_table_association" "public_subnet_association" {
 subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_route_table.id
}


resource "aws_flow_log" "main" {
  log_destination          = aws_cloudwatch_log_group.example.arn
  log_destination_type     = "cloud-watch-logs"
  traffic_type            = "ALL"
  vpc_id                  = aws_vpc.main.id
  max_aggregation_interval = 600
}


resource "aws_cloudwatch_log_group" "example" {
  name              = "/aws/flowlogs/${aws_vpc.main.id}"
  retention_in_days = var.log_retention_days
}



# Security Groups
resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow inbound HTTPS and SSH from specific CIDRs, and all outbound traffic"
  vpc_id      = aws_vpc.main.id


  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks # restrict to load balancer


  }

  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol        = "tcp"
    cidr_blocks      = var.allowed_cidr_blocks
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol        = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
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
  description = "Allow inbound MySQL/Aurora from web servers, and all outbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
    description = "MySQL/Aurora access from web servers"

  }

 egress {
    from_port        = 0
    to_port          = 0
    protocol        = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  description = "All outbound traffic"
  }

  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}


# RDS Instance
resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_1.id]

  tags = {
    Name = "${var.project_name}-db-subnet-group"
    Environment = var.environment
    Project     = var.project_name
  }
}




resource "aws_db_instance" "default" {
  allocated_storage                = 20
  storage_type                     = "gp2"
  engine                           = "mysql"
  engine_version                   = "8.0"
  instance_class                   = "db.t2.micro"
  name                             = "wordpressdb"
  username                         = var.rds_username
  password                         = var.rds_password
  db_subnet_group_name             = aws_db_subnet_group.default.name
  vpc_security_group_ids           = [aws_security_group.rds_sg.id]
  skip_final_snapshot              = true
  storage_encrypted                = true
  backup_retention_period          = 7
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports    = ["audit", "error", "general", "slowquery"]


  tags = {
    Name = "${var.project_name}-rds"
    Environment = var.environment
    Project     = var.project_name
  }
}




# EC2 Instances & Autoscaling
resource "aws_instance" "web_server" {
  ami                         = var.ami_id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_1.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  associate_public_ip_address = true # Keep this true for now to maintain original functionality
  user_data = <<EOF
#!/bin/bash
sudo yum update -y
sudo amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2
sudo yum install -y httpd mariadb-server
sudo systemctl start httpd
sudo systemctl enable httpd
sudo systemctl start mariadb
sudo systemctl enable mariadb
EOF
ebs_optimized = true
  monitoring = true

  tags = {
    Name = "${var.project_name}-web-server"
    Environment = var.environment
    Project     = var.project_name
  }


  lifecycle {
    create_before_destroy = true
  }
}



# Load Balancer
resource "aws_lb" "main" {
  name                    = "${var.project_name}-lb"
  internal                = false
  load_balancer_type    = "application"
  security_groups         = [aws_security_group.web_sg.id]
  subnets                 = [aws_subnet.public_1.id]
  enable_deletion_protection = true
 drop_invalid_header_fields = true


  tags = {
    Name = "${var.project_name}-lb"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_lb_target_group" "main" {
  name     = "${var.project_name}-lb-tg"
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
    Name = "${var.project_name}-lb-tg"
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
  certificate_arn   = "arn:aws:iam::123456789012:server-certificate/test_cert" # Replace with a real ACM certificate ARN

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}


resource "aws_lb_target_group_attachment" "main" {
  target_group_arn = aws_lb_target_group.main.id
  target_id        = aws_instance.web_server.id
  port             = 80
}



resource "aws_wafv2_web_acl" "example" {
  name        = "example"
  description = "Example of a managed rule group association"
  scope        = "REGIONAL"
  default_action {
    block {}
  }
  visibility_config {
    cloudwatch_metrics_enabled = false
    metric_name                = "friendly-metric-name"
    sampled_requests_enabled   = false
  }
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    statement {
 managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
 vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = false
    }
  }
}


resource "aws_wafv2_web_acl_association" "example" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.example.arn
}



variable "log_retention_days" {
  type        = number
  description = "Number of days to retain logs."
  default     = 7
}




# Outputs
output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC."
}

output "load_balancer_dns_name" {
  value       = aws_lb.main.dns_name
  description = "The DNS name of the load balancer."
}

output "rds_endpoint" {
  value       = aws_db_instance.default.endpoint
  description = "The endpoint of the RDS instance."
}
