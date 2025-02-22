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
  description = "The AWS region to deploy into."
  default     = "us-west-2"
}

variable "project_name" {
  type        = string
  description = "The name of the project."

  default = "wordpress-project"
}

variable "environment" {
  type        = string
  description = "The environment name (e.g., production, development)."
  default     = "production"
}


variable "rds_username" {
  type        = string
  description = "The RDS instance username."
  sensitive   = true

}

variable "rds_password" {
  type        = string
  description = "The RDS instance password."
  sensitive   = true

}
variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of allowed CIDR blocks for SSH access."
  default = ["0.0.0.0/0"] # Default allows all, but can be locked down by overriding var
}

variable "http_allowed_cidr_blocks" {
 type = list(string)
  description = "CIDR blocks allowed to access HTTP (port 80)."
 default = ["0.0.0.0/0"]
}

variable "https_allowed_cidr_blocks" {
 type = list(string)
  description = "CIDR blocks allowed to access HTTPS (port 443)."
  default = ["0.0.0.0/0"]
}




# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    Project     = var.project_name
  }
 enable_dns_hostnames = true
  enable_dns_support   = true


}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
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
  availability_zone = "${var.region}a"
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


# Security Groups

resource "aws_security_group" "web_sg" {
 name        = "${var.project_name}-web-sg"
  description = "Allow inbound HTTP, HTTPS, and SSH"
  vpc_id      = aws_vpc.main.id

 ingress {
 from_port   = 80
 to_port     = 80
    protocol    = "tcp"
 cidr_blocks = var.http_allowed_cidr_blocks
 description = "Allow HTTP traffic"
  }

 ingress {
    from_port   = 443
 to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.https_allowed_cidr_blocks
 description = "Allow HTTPS traffic"

  }

 ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
 cidr_blocks = var.allowed_cidr_blocks
 description = "Allow SSH traffic"

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
  description = "Allow MySQL traffic from web servers"


  }

  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}



# EC2 Instances

resource "aws_instance" "web_server" {
  ami                         = "ami-0c94855ba95c574c8" # Replace with your desired AMI
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_1.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  associate_public_ip_address = true

 ebs_optimized = true
  monitoring = true

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


  tags = {
    Name        = "${var.project_name}-web-server"
    Environment = var.environment
    Project     = var.project_name
  }
}


# RDS Instance

resource "aws_db_instance" "default" {
 allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
 engine_version       = "8.0" # Or mysql version of your choice
  instance_class       = "db.t3.micro"
  name                 = "wordpress"
 username             = var.rds_username
  password             = var.rds_password
  parameter_group_name = "default.mysql8.0" # Adjust if needed
 vpc_security_group_ids      = [aws_security_group.rds_sg.id]
 skip_final_snapshot        = true
  db_subnet_group_name      = aws_db_subnet_group.default.name
 storage_encrypted          = true
 backup_retention_period    = 12
  iam_database_authentication_enabled = true
 enabled_cloudwatch_logs_exports    = ["audit", "error", "general", "slowquery"]
 deletion_protection = false


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



# ... (Rest of the resources: ELB, ASG, CloudFront, S3, Route53)


output "ec2_public_ip" {
  value       = aws_instance.web_server.public_ip
  description = "Public IP address of the EC2 instance."
}

output "rds_endpoint" {
  value       = aws_db_instance.default.endpoint
  description = "Endpoint of the RDS instance."
}


