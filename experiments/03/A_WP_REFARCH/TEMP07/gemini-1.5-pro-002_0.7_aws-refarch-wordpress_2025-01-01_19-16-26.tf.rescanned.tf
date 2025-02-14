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
  description = "The AWS region to deploy the resources in."
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

variable "db_username" {
  type        = string
  description = "The database username."
  sensitive   = true
}

variable "db_password" {
  type        = string
  description = "The database password. Must be at least 8 characters long and contain uppercase, lowercase, numbers, and symbols."
  sensitive   = true
}

# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false # Disable public IP assignment
 tags = {
    Name        = "${var.project_name}-public-subnet-1"
    Environment = var.environment
  }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project_name}-private-subnet-1"
    Environment = var.environment
  }
}

resource "aws_db_subnet_group" "default" {

  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_1.id]
  tags = {
    Name        = "${var.project_name}-db-subnet-group"
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

resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_route_table.id
}


# Security Groups
resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow inbound HTTPS and SSH, restrict outbound"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] # Open to public for HTTPS
    description      = "Allow HTTPS from anywhere"
  }

    ingress {
        from_port        = 22
        to_port          = 22
        protocol         = "tcp"
        cidr_blocks      = ["0.0.0.0/0"]
        description      = "Allow SSH from anywhere temporarily"
    }


  egress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    description      = "Allow outbound HTTPS to anywhere"
  }




  tags = {
    Name        = "${var.project_name}-web-sg"
    Environment = var.environment
  }
}

resource "aws_security_group" "rds_sg" {
    name        = "${var.project_name}-rds-sg"
    description = "Allow inbound traffic from web server on MySQL port 3306"
    vpc_id      = aws_vpc.main.id

    ingress {
        from_port        = 3306
        to_port          = 3306
        protocol         = "tcp"
        security_groups = [aws_security_group.web_sg.id] # Allow access from web server security group
        description      = "Allow MySQL access from web server"
    }

    egress {
        from_port        = 0
        to_port          = 0
        protocol         = "-1"
        cidr_blocks      = ["0.0.0.0/0"] # Allow all outbound traffic for now
        description      = "Allow all outbound traffic temporarily"
    }


    tags = {
        Name        = "${var.project_name}-rds-sg"
        Environment = var.environment
    }
}



# EC2 Instances and Autoscaling
resource "aws_instance" "web" {
  ami                         = "ami-0c94855ba95c574c8" # Replace with your desired AMI
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_1.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]

  user_data = <<-EOF
#!/bin/bash
sudo yum update -y
sudo amazon-linux-extras install -y php8.1
sudo yum install -y httpd php-mysqlnd
sudo systemctl start httpd
sudo systemctl enable httpd
sudo echo "<html><body><h1>Hello from Terraform!</h1></body></html>" > /var/www/html/index.html

  EOF
  monitoring = true
 ebs_optimized = true
  associate_public_ip_address = false
  tags = {
    Name        = "${var.project_name}-web-server"
    Environment = var.environment
  }
}


# RDS Instance
resource "aws_db_instance" "default" {
  allocated_storage             = 20
  storage_type                  = "gp2"
  engine                        = "mysql"
  engine_version                = "8.0.28" # Example version, adjust as needed
  instance_class                = "db.t3.micro"
  username                      = var.db_username
  password                      = var.db_password
  db_name                       = "wordpressdb"
  skip_final_snapshot           = true
  publicly_accessible          = false # Ensure private access
  storage_encrypted             = true
  backup_retention_period       = 7
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports    = ["general", "error", "slowquery"]
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.default.id

  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
  }

}



# Output
output "ec2_public_ip" {
  value       = aws_instance.web.private_ip
  description = "The private IP address of the EC2 instance."
}

output "rds_endpoint" {
  value       = aws_db_instance.default.endpoint
  description = "The endpoint of the RDS instance."
}
