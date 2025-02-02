terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "db_instance_class" {
 type = string
 default = "db.t3.micro"
}


resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "wordpress-vpc"
  }
}


resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "wordpress-public-subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index + length(var.public_subnet_cidrs)]

  tags = {
    Name = "wordpress-private-subnet-${count.index + 1}"
  }
}

data "aws_availability_zones" "available" {}

resource "aws_internet_gateway" "gw" {
 vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name = "wordpress-igw"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "wordpress-public-route-table"
  }
}



resource "aws_route_table_association" "public_subnet_association" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}


resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

 ingress {
    description      = "TLS from VPC"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = [aws_vpc.wordpress_vpc.cidr_block]
    ipv6_cidr_blocks = [aws_vpc.wordpress_vpc.ipv6_cidr_block[0]]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }


  tags = {
    Name = "allow_tls"
  }
}


resource "aws_instance" "web_server" {
  ami                         = "ami-0c94855ba95c574c8" # Example AMI, replace with appropriate AMI for region and OS
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_subnets[0].id # Place in public subnet
  vpc_security_group_ids      = [aws_security_group.allow_tls.id]
  associate_public_ip_address = true
  user_data = <<-EOF
#!/bin/bash
sudo apt update
sudo apt install -y apache2 php libapache2-mod-php php-mysql
sudo systemctl start apache2
sudo systemctl enable apache2
echo "<html><body><h1>Hello from Terraform!</h1></body></html>" | sudo tee /var/www/html/index.html
  EOF

  tags = {
    Name = "wordpress-web-server"
  }

}



resource "aws_db_instance" "default" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "8.0" # Or latest
  instance_class       = var.db_instance_class
  name                 = "wordpressdb"
  username             = "admin" # Replace with a strong, randomly generated password
  password             = random_password.password.result # Use random passwords
  parameter_group_name = "default.mysql8.0" # Adjust for engine version
  skip_final_snapshot  = true
  vpc_security_group_ids = [aws_security_group.allow_tls.id] # Ensure correct SG
 db_subnet_group_name = aws_db_subnet_group.default.name

  tags = {
    Name = "wordpress-db"
  }
}


resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "!#$%&()*+,-./:;<=>?@[]^_{|}~"
}



resource "aws_db_subnet_group" "default" {
  name       = "main"
  subnet_ids = aws_subnet.private_subnets[*].id

  tags = {
    Name = "wordpress-db-subnet-group"
  }
}


resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${random_id.bucket_suffix.hex}"
 acl    = "private"


  tags = {
    Name = "wordpress-assets-bucket"
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 8
}

output "s3_bucket_name" {
 value = aws_s3_bucket.wordpress_assets.bucket
}


