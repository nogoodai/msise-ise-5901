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
  type    = string
  default = "us-west-2"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-west-2a", "us-west-2b"]
}

variable "public_subnet_cidrs" {
  type = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]

}


variable "private_subnet_cidrs" {
  type = list(string)
  default = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "instance_type" {
  type = string
  default = "t3.micro"
}

variable "db_instance_class" {
    type = string
    default = "db.t3.micro"
}


# VPC and Networking
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "wordpress-vpc"
  }
}



resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name = "wordpress-igw"
  }
}

resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "wordpress-public-subnet-${count.index}"
  }

}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "wordpress-private-subnet-${count.index}"

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


# Security Groups

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

resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id


  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }

    egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_ssh"
  }
}



# EC2 and Autoscaling

resource "aws_instance" "wordpress_instance" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id = aws_subnet.public_subnets[0].id # Deploy to the first public subnet
  vpc_security_group_ids = [aws_security_group.allow_tls.id, aws_security_group.allow_ssh.id]
  user_data = <<-EOF
#!/bin/bash
yum update -y
yum install httpd php mysql -y
systemctl start httpd
echo "Hello World from $(hostname -f)" > /var/www/html/index.html
  EOF

  tags = {
    Name = "wordpress-instance"
  }

}


# RDS


resource "aws_db_subnet_group" "default" {

  name       = "main"
  subnet_ids = aws_subnet.private_subnets[*].id

  tags = {
    Name = "My DB Subnet Group"
  }
}



resource "aws_db_instance" "default" {
  allocated_storage    = 20
  storage_encrypted   = true
  engine               = "mysql"
    instance_class      = var.db_instance_class
  db_subnet_group_name = aws_db_subnet_group.default.name
  identifier           = "wordpress-db"
  username             = "admin" # Replace with your desired username


  # Set a secure randomly generated password
  password             = random_password.password.result


  skip_final_snapshot = true



  tags = {
    Name = "wordpress-db"
  }
}

resource "random_password" "password" {
 length = 16
  special = true
  override_special = "!#$%&*()-=" # Example of allowed special characters
}





# Placeholder for other required components (ELB, CloudFront, S3, Route53) -  These would require significantly more configuration details to be implemented securely.

output "website_url" {
 value = aws_instance.wordpress_instance.public_ip
}
