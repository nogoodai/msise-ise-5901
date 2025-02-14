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
  type        = string
  default     = "us-west-2"
  description = "The AWS region to deploy into."
}

variable "project_name" {
  type        = string
  default     = "wordpress-project"
  description = "The name of the project."
}

variable "environment" {
  type        = string
  default     = "production"
  description = "The environment name (e.g., production, development)."

}

variable "db_password" {
  type        = string
  description = "Password for the RDS database.  This should be set via a secure method such as environment variables or a secrets manager."
  sensitive   = true
}


variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of allowed CIDR blocks for SSH access."

}

variable "key_name" {
 type = string
 description = "SSH Key Pair name"
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


data "aws_availability_zones" "available" {}

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


# Security Groups

resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow inbound HTTPS and SSH from specific CIDR blocks"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] # Open to all for now, restrict later with WAF
    description      = "Allow HTTPS traffic from anywhere"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Allow SSH traffic from allowed CIDR blocks"

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
  description = "Allow MySQL traffic from web servers"

  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
 description = "Allow all outbound traffic"

  }

  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}




# EC2 Instances & Autoscaling

resource "aws_instance" "web_server" {


  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_1.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  associate_public_ip_address = true
  key_name = var.key_name
 monitoring = true
  ebs_optimized = true


  user_data = <<-EOF
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
  allocated_storage              = 20
  storage_type                   = "gp2"
  engine                         = "mysql"
  engine_version                 = "8.0" # Or latest
  instance_class                 = "db.t2.micro"
 username                       = "admin" # Replace with IAM auth later
  password                       = var.db_password
  db_name                        = "wordpressdb"
  skip_final_snapshot            = true
  vpc_security_group_ids         = [aws_security_group.rds_sg.id]
  db_subnet_group_name           = aws_db_subnet_group.default.name
 storage_encrypted = true
  backup_retention_period = 7
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
  subnet_ids = [aws_subnet.private_1.id]

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
        Environment = var.environment
    Project     = var.project_name
  }

}



# Elastic Load Balancer

resource "aws_lb" "web" {

  name                      = "${var.project_name}-lb"
  internal                  = false
  load_balancer_type        = "application"
  security_groups           = [aws_security_group.web_sg.id]
 subnets                  = [aws_subnet.public_1.id]
  enable_deletion_protection = true
  drop_invalid_header_fields = true


  tags = {
    Name        = "${var.project_name}-lb"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_lb_target_group" "web" {
  name        = "${var.project_name}-lb-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"


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
    Name        = "${var.project_name}-lb-tg"
    Environment = var.environment
    Project     = var.project_name
  }
}



resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = "80"
  protocol          = "HTTP"



  default_action {
    type             = "redirect"
    redirect {
      port = "443"
      protocol = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}



resource "aws_s3_bucket" "web_bucket" {
  bucket = "${var.project_name}-s3-bucket"
  acl    = "private"


  versioning {
    enabled = true
  }


  logging {
    target_bucket = "s3-log-bucket" # Replace with your logging bucket name
    target_prefix = "log/"
  }

  tags = {
    Name        = "${var.project_name}-s3-bucket"
    Environment = var.environment
    Project     = var.project_name
  }

}



# Output


output "vpc_id" {
  value       = aws_vpc.main.id
  description = "ID of the VPC"

}


output "load_balancer_dns_name" {
  value       = aws_lb.web.dns_name
  description = "DNS name of the load balancer"

}

output "rds_endpoint" {
  value       = aws_db_instance.default.address
  description = "Endpoint of the RDS instance"
}

output "s3_bucket_arn" {
  value       = aws_s3_bucket.web_bucket.arn
  description = "ARN of the S3 Bucket"

}


