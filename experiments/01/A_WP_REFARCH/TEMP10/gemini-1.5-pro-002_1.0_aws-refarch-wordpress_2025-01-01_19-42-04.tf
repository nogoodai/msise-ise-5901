terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
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

variable "availability_zones" {
  type    = list(string)
  default = ["us-west-2a", "us-west-2b"]

}


resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "WordPressVPC"
  }
}


resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "public-subnet-${count.index}"
  }
}


resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]


  tags = {
    Name = "private-subnet-${count.index}"
  }
}

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
    Name = "public-route-table"
  }
}



resource "aws_route_table_association" "public_subnet_association" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}




# Security Groups

resource "aws_security_group" "web_server_sg" {
 name = "web-server-sg"
  description = "Allow inbound HTTP, HTTPS, and SSH"
  vpc_id      = aws_vpc.wordpress_vpc.id

 ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol        = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] # Replace with your IP
  }


 egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }



  tags = {
    Name = "web-server-security-group"
  }
}




resource "aws_instance" "wordpress_instances" {

  ami           = "ami-0c94855ba95c574c8" # Replace with your desired AMI
  instance_type = "t2.micro"


  # Add other EC2 configurations as needed (user data, key pairs, etc.)
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  subnet_id = aws_subnet.public_subnets[0].id

  user_data = <<-EOF
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
    Name = "wordpress-instance"
  }
}






resource "aws_db_instance" "wordpress_db" {

  identifier             = "wordpress-db"

  engine                 = "mysql"
  engine_version        = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  username               = "admin" # Replace with your desired username
  password               = "password" # Replace with a strong password
  db_subnet_group_name  = aws_db_subnet_group.default.name

  vpc_security_group_ids = [aws_security_group.web_server_sg.id]

 skip_final_snapshot    = true



  tags = {
    Name = "wordpress-db"
  }
}


resource "aws_db_subnet_group" "default" {

  name       = "main"
  subnet_ids = aws_subnet.private_subnets[*].id



  tags = {
    Name = "main"
  }
}



resource "aws_lb" "wordpress_lb" {


  load_balancer_type = "application"

  name               = "wordpress-lb"
  internal           = false

  security_groups = [aws_security_group.web_server_sg.id]
 subnets           = aws_subnet.public_subnets[*].id


  tags = {
    Name = "wordpress-lb"
  }
}





resource "aws_lb_target_group" "wordpress_tg" {

  name        = "wordpress-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.wordpress_vpc.id
 target_type = "instance"



  health_check {
    path                = "/"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 2
    timeout             = 5
    matcher             = "200"
  }

}



resource "aws_lb_listener" "http" {

  load_balancer_arn = aws_lb.wordpress_lb.arn
  port              = "80"
  protocol          = "HTTP"


 default_action {

    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}


resource "aws_lb_target_group_attachment" "wordpress_tg_attachment" {

  target_group_arn = aws_lb_target_group.wordpress_tg.arn
  target_id        = aws_instance.wordpress_instances.id
  port             = 80
}






output "lb_dns_name" {
  value = aws_lb.wordpress_lb.dns_name
}





