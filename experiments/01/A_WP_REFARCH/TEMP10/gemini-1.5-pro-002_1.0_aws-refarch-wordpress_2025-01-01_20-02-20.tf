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
  type    = string
  default = "us-west-2"
}

variable "project_name" {
  type    = string
  default = "wordpress-project"
}

variable "environment" {
  type    = string
  default = "dev"
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
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

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

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
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


# Security Groups

resource "aws_security_group" "web_server_sg" {
 name        = "${var.project_name}-web-server-sg"
  description = "Allow inbound HTTP, HTTPS, and SSH"
  vpc_id      = aws_vpc.main.id

 ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Replace with your IP
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }


  tags = {
    Name        = "${var.project_name}-web-server-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}




# EC2 Instances & Auto Scaling

resource "aws_launch_template" "wordpress_lt" {
  name = "${var.project_name}-wordpress-lt"


  image_id      = "ami-0c94855ba95c574c8" # Replace with your desired AMI
  instance_type = "t2.micro"


  network_interfaces {
    security_groups = [aws_security_group.web_server_sg.id]
    associate_public_ip_address = true


  }


 user_data = filebase64("./user_data.sh")

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
}




resource "aws_autoscaling_group" "wordpress_asg" {
  name                 = "${var.project_name}-wordpress-asg"

  vpc_zone_identifier = [aws_subnet.public_1.id]
  min_size             = 1
  max_size             = 3



  launch_template {
 id      = aws_launch_template.wordpress_lt.id
    version = "$Latest"
  }



  tag {
    key                 = "Name"
    value               = "${var.project_name}-wordpress-asg"
    propagate_at_launch = true
  }


  lifecycle {
    create_before_destroy = true
  }
}






# RDS Instance



resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-rds-subnet-group"
  subnet_ids = [aws_subnet.private_1.id]




  tags = {
    Name        = "${var.project_name}-rds-subnet-group"
    Environment = var.environment
    Project     = var.project_name
  }
}



resource "aws_db_instance" "default" {
  identifier = "${var.project_name}-rds"
  allocated_storage = 20
  storage_type = "gp2"

  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t2.micro"
  username             = "admin" # Replace with your username
  password             = "password123" # Replace with your password
  db_subnet_group_name = aws_db_subnet_group.default.name
  vpc_security_group_ids =[aws_security_group.web_server_sg.id]


  skip_final_snapshot = true


  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Load Balancer

resource "aws_lb" "wordpress_lb" {
  name               = "${var.project_name}-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_server_sg.id]
 subnets            = [aws_subnet.public_1.id]


  tags = {
    Name        = "${var.project_name}-lb"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_lb_target_group" "wordpress_tg" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id


  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
  }




  tags = {
    Name        = "${var.project_name}-tg"
    Environment = var.environment
    Project     = var.project_name
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


resource "aws_autoscaling_attachment" "asg_attachment_lb" {
  autoscaling_group_name = aws_autoscaling_group.wordpress_asg.id
  lb_target_group_arn     = aws_lb_target_group.wordpress_tg.arn
}


# S3 bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "${var.project_name}-bucket"




  tags = {
    Name        = "${var.project_name}-bucket"
    Environment = var.environment
    Project     = var.project_name
  }
}


output "vpc_id" {
  value = aws_vpc.main.id
}

output "load_balancer_dns_name" {
  value = aws_lb.wordpress_lb.dns_name
}
output "rds_endpoint" {
  value = aws_db_instance.default.endpoint
}

output "s3_bucket_arn" {
 value = aws_s3_bucket.wordpress_bucket.arn
}



