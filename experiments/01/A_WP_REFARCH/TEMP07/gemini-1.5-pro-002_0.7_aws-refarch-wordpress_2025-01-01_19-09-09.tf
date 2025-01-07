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
  availability_zone = "${var.region}a"
  tags = {
    Name        = "${var.project_name}-public-subnet-1"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "public_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.region}b"
  tags = {
    Name        = "${var.project_name}-public-subnet-2"
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

resource "aws_route_table_association" "public_subnet_1_association" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_2_association" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_route_table.id
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
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-web-server-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow inbound MySQL/Aurora from web servers"
  vpc_id      = aws_vpc.main.id

 ingress {
    from_port        = 3306
 to_port          = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
  }

  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}


# EC2 Instances and Auto Scaling

resource "aws_launch_template" "wordpress_lt" {
  name_prefix   = "${var.project_name}-wordpress-lt-"
  image_id      = data.aws_ami.amazon_linux_latest.id
 instance_type = "t2.micro"
  network_interfaces {
    security_groups = [aws_security_group.web_server_sg.id]
    associate_public_ip_address = true
  }


  user_data = filebase64("user_data.sh") # Create this file

 lifecycle {
 create_before_destroy = true
  }
}

resource "aws_ami" "amazon_linux_latest" {
 most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}


resource "aws_autoscaling_group" "wordpress_asg" {
 name                      = "${var.project_name}-wordpress-asg"
 launch_template {
 id      = aws_launch_template.wordpress_lt.id
 version = "$Latest"
  }
 min_size                  = 2
 max_size                  = 4
 vpc_zone_identifier = [aws_subnet.public_1.id, aws_subnet.public_2.id]

 tag {
    key                 = "Name"
    value              = "${var.project_name}-wordpress-instance"
    propagate_at_launch = true
  }
}



# RDS Instance

resource "aws_db_instance" "default" {
  allocated_storage    = 20
  storage_type        = "gp2"
  engine              = "mysql"
  engine_version      = "8.0.28" # Example version
  instance_class      = "db.t2.micro"
  name                = "wordpress"
  username            = var.db_username
  password            = var.db_password
  db_subnet_group_name = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot = true
 multi_az              = false
}


variable "db_username" {
  type = string
 default = "admin"
}


variable "db_password" {
  type = string
 default = "password123" # Replace with a strong password
}


resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}


# Elastic Load Balancer

resource "aws_lb" "wordpress_lb" {
 name               = "${var.project_name}-wordpress-lb"
 internal           = false
 load_balancer_type = "application"
 security_groups = [aws_security_group.web_server_sg.id]
 subnets = [aws_subnet.public_1.id, aws_subnet.public_2.id]


  tags = {
    Name        = "${var.project_name}-alb"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_lb_target_group" "wordpress_tg" {
 name     = "${var.project_name}-wordpress-tg"
 port     = 80
 protocol = "HTTP"
 vpc_id   = aws_vpc.main.id

 health_check {
    path                = "/"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
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



resource "aws_autoscaling_attachment" "asg_attachment" {
 autoscaling_group_name = aws_autoscaling_group.wordpress_asg.name
 load_balancer_target_group_arn = aws_lb_target_group.wordpress_tg.arn
}




# S3 Bucket

resource "aws_s3_bucket" "wordpress_assets" {
 bucket = "${var.project_name}-wordpress-assets"
 acl    = "private"


  tags = {
    Name        = "${var.project_name}-s3-bucket"
 Environment = var.environment
 Project     = var.project_name
  }
}



# Placeholder for CloudFront and Route53.  This requires more user input for domain names, etc.


output "alb_dns_name" {
 value = aws_lb.wordpress_lb.dns_name
}

output "rds_endpoint" {
  value = aws_db_instance.default.endpoint
}

