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
  description = "Password for the RDS database. Must be at least 8 characters."
 sensitive   = true

}
variable "allowed_cidr_blocks" {
  type = list(string)
  description = "List of CIDR blocks allowed to access resources"
  default = [] # Set to an empty list; uncomment and populate as needed
}
variable "ssh_allowed_cidr_blocks" {
  type = list(string)
  description = "List of CIDR blocks allowed SSH access"
  default = [] # Set to an empty list; uncomment and populate as needed
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
  availability_zone       = "${var.region}a"
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
  availability_zone = "${var.region}a"

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


resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_route_table.id
}


# Security Groups
resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow HTTP and HTTPS inbound"
  vpc_id      = aws_vpc.main.id


  dynamic "ingress" {
    for_each = var.allowed_cidr_blocks
    content {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
      description = "Allow HTTP from specific CIDR"
    }
  }

  dynamic "ingress" {
    for_each = var.allowed_cidr_blocks
    content {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
      description = "Allow HTTPS from specific CIDR"


    }
  }

  dynamic "ingress" {
    for_each = var.ssh_allowed_cidr_blocks
 content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
      description = "Allow SSH from specific CIDR"
    }
  }



  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
 description = "Allow all outbound traffic"
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
    description = "Allow MySQL access from web servers"

  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
 description = "Allow all outbound traffic"
  }


  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}


# EC2 Instances and Auto Scaling
resource "aws_instance" "web_server" {


  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  associate_public_ip_address = false
 monitoring = true
  user_data = <<EOF
#!/bin/bash
sudo yum update -y
sudo yum install httpd -y
sudo systemctl start httpd
sudo systemctl enable httpd
echo "<h1>Hello from $(hostname -f)</h1>" > /var/www/html/index.html
EOF

  tags = {
    Name        = "${var.project_name}-web-server"
    Environment = var.environment
    Project     = var.project_name
  }
}


data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
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
  username                         = "admin"
  password                         = var.db_password
  db_subnet_group_name             = aws_db_subnet_group.default.name
  vpc_security_group_ids           = [aws_security_group.rds_sg.id]
  skip_final_snapshot              = true
  storage_encrypted                = true
  iam_database_authentication_enabled = true
 backup_retention_period = 7
 enabled_cloudwatch_logs_exports    = ["audit", "error", "general", "slowquery"]

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

# Outputs
output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC"
}

output "web_server_private_ip" {
  value = aws_instance.web_server.private_ip
  description = "The private IP address of the web server"
}
output "web_server_public_ip" {
  value = aws_instance.web_server.public_ip
  description = "The public IP address of the web server"
}


output "rds_endpoint" {
  value       = aws_db_instance.default.endpoint
  description = "The endpoint of the RDS instance"
}


