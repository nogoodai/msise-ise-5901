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
  default = "production"
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

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.101.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project_name}-private-subnet-1"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.102.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  tags = {
    Name        = "${var.project_name}-private-subnet-2"
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

resource "aws_security_group" "web_sg" {
 name        = "${var.project_name}-web-sg"
  description = "Allow inbound HTTP, HTTPS and SSH"
  vpc_id      = aws_vpc.main.id

 ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

 ingress {
    description      = "SSH from my IP"
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
    Name        = "${var.project_name}-web-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow inbound MySQL/Aurora"
  vpc_id      = aws_vpc.main.id

  ingress {
    description      = "MySQL/Aurora from web servers"
    from_port        = 3306
    to_port          = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol        = "-1"
 security_groups = [aws_security_group.web_sg.id]
  }

  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}


# EC2 Instances and Auto Scaling

resource "aws_instance" "web_server" {
  ami           = "ami-0c94855ba95c574c8" # Replace with your desired AMI
  instance_type = "t2.micro"
  subnet_id = aws_subnet.public_1.id # Replace with your subnet ID
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  user_data = file("user_data.sh") # Replace with your user data script
  tags = {
    Name        = "${var.project_name}-web-server"
    Environment = var.environment
    Project     = var.project_name
  }

  lifecycle {
    create_before_destroy = true
  }
}

# RDS Instance

resource "aws_db_instance" "default" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "8.0" # Replace with your desired engine version
  instance_class       = "db.t2.micro"
  name                 = "wordpressdb"
  username             = "admin" # Replace with your desired username
  password             = "password123" # Replace with your desired password.  Use a secure password generation mechanism in production.
  db_subnet_group_name = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot  = true
  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
    Project     = var.project_name
  }
}


# Elastic Load Balancer

resource "aws_lb" "web" {
  name               = "${var.project_name}-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]

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
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}


resource "aws_lb_listener_rule" "instance_rule" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

# Autoscaling Group

resource "aws_autoscaling_group" "web" {
  name                 = "${var.project_name}-asg"
  min_size             = 1
  max_size             = 3
  vpc_zone_identifier  = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  load_balancer_arns = [aws_lb.web.arn]
  health_check_type = "ELB"
  target_group_arns = [aws_lb_target_group.web.arn]

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-asg-instance"
    propagate_at_launch = true
  }
}


resource "aws_launch_template" "web" {
  name_prefix   = "${var.project_name}-launch-template-"
  image_id      = "ami-0c94855ba95c574c8" # Replace with your desired AMI
  instance_type = "t2.micro"
  network_interfaces {
    security_groups = [aws_security_group.web_sg.id]
  }
  user_data = base64encode(file("user_data.sh")) # Replace with your user data script
}

# S3 Bucket

resource "aws_s3_bucket" "static_assets" {
  bucket = "${var.project_name}-static-assets"
  acl    = "private"

  tags = {
    Name        = "${var.project_name}-s3-bucket"
    Environment = var.environment
    Project     = var.project_name
  }
}


# Outputs

output "vpc_id" {
  value = aws_vpc.main.id
}

output "load_balancer_dns_name" {
  value = aws_lb.web.dns_name
}

output "rds_endpoint" {
  value = aws_db_instance.default.endpoint
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.static_assets.arn
}

