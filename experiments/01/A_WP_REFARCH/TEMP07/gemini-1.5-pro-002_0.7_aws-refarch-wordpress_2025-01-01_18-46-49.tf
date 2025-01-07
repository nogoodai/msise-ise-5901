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
  cidr_block        = "10.0.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project_name}-private-subnet-1"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.20.0/24"
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


resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block        = "0.0.0.0/0"
    gateway_id         = aws_internet_gateway.gw.id
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

resource "aws_security_group" "web_sg" {
 name = "${var.project_name}-web-sg"
  description = "Allow inbound HTTP, HTTPS, and SSH"
  vpc_id = aws_vpc.main.id


 ingress {
    from_port = 80
 to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
 from_port = 443
    to_port = 443
 protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
 from_port = 22
 to_port = 22
    protocol = "tcp"
 cidr_blocks = ["0.0.0.0/0"] # Replace with your IP or CIDR block
  }

  egress {
 from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-web-sg"
 Environment = var.environment
 Project = var.project_name
  }
}



resource "aws_security_group" "rds_sg" {
  name = "${var.project_name}-rds-sg"
 description = "Allow inbound MySQL/Aurora from web servers"
 vpc_id = aws_vpc.main.id

 ingress {
 from_port = 3306
 to_port = 3306
 protocol = "tcp"
 security_groups = [aws_security_group.web_sg.id]
  }


  tags = {
 Name = "${var.project_name}-rds-sg"
    Environment = var.environment
 Project = var.project_name
  }
}

resource "aws_security_group" "alb_sg" {
 name = "${var.project_name}-alb-sg"
 description = "Allow inbound HTTP/HTTPS for ALB"
 vpc_id = aws_vpc.main.id


  ingress {
 from_port = 80
    to_port = 80
    protocol = "tcp"
 cidr_blocks = ["0.0.0.0/0"]
  }

 ingress {
    from_port = 443
 to_port = 443
 protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
 from_port = 0
 to_port = 0
 protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

 tags = {
 Name = "${var.project_name}-alb-sg"
 Environment = var.environment
    Project = var.project_name
 }
}


# EC2 Instances & Auto Scaling

resource "aws_launch_template" "wordpress_lt" {
 name_prefix = "${var.project_name}-wordpress-lt-"
  image_id = "ami-0c94855ba95c574c7" # Replace with your desired AMI
 instance_type = "t2.micro"
 network_interfaces {
    security_groups = [aws_security_group.web_sg.id]
    associate_public_ip_address = false
 subnet_id = aws_subnet.private_1.id
  }

 user_data = filebase64("./wordpress_install.sh") # Replace with your user data script
 tag_specifications {
 resource_type = "instance"
    tags = {
 Name = "${var.project_name}-wordpress-instance"
      Environment = var.environment
 Project = var.project_name
    }
  }

 lifecycle {
 create_before_destroy = true
 }
}

resource "aws_autoscaling_group" "wordpress_asg" {
 name = "${var.project_name}-wordpress-asg"
  vpc_zone_identifier = [aws_subnet.private_1.id, aws_subnet.private_2.id]
 launch_template {
 id = aws_launch_template.wordpress_lt.id
 version = "$Latest"
 }
 min_size = 2
 max_size = 4
 health_check_type = "ELB"
 target_group_arns = [aws_lb_target_group.wordpress_tg.arn]

  tag {
    key                 = "Name"
    value              = "${var.project_name}-asg"
    propagate_at_launch = true
 }
 tag {
 key = "Environment"
    value = var.environment
    propagate_at_launch = true
  }
  tag {
    key                 = "Project"
    value              = var.project_name
    propagate_at_launch = true
  }
}

# RDS Instance

resource "aws_db_instance" "wordpress_db" {
 allocated_storage = 20
  storage_type = "gp2"
 engine = "mysql"
  engine_version = "8.0.32" # Replace with your desired version
 instance_class = "db.t2.micro"
 name = "wordpressdb"
 username = "admin" # Replace with your desired username
 password = "password123" # Replace with a strong password
 db_subnet_group_name = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
 skip_final_snapshot = true
 multi_az = true
  tags = {
    Name = "${var.project_name}-rds"
    Environment = var.environment
    Project = var.project_name
  }
}

resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]

  tags = {
 Name = "${var.project_name}-db-subnet-group"
 Environment = var.environment
 Project = var.project_name
 }
}

# Elastic Load Balancer

resource "aws_lb" "wordpress_alb" {
 name = "${var.project_name}-alb"
 internal = false
 load_balancer_type = "application"
 security_groups = [aws_security_group.alb_sg.id]
 subnets = [aws_subnet.public_1.id, aws_subnet.public_2.id]


  tags = {
 Name = "${var.project_name}-alb"
 Environment = var.environment
 Project = var.project_name
  }
}

resource "aws_lb_listener" "http" {
 load_balancer_arn = aws_lb.wordpress_alb.arn
  port = 80
 protocol = "HTTP"

 default_action {
    type = "redirect"

    redirect {
 port = "443"
 protocol = "HTTPS"
 status_code = "HTTP_301"
    }
  }
}


resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
 port = 443
  protocol = "HTTPS"
 ssl_policy = "ELBSecurityPolicy-2016-08"
 certificate_arn = "arn:aws:iam::xxxxxxxxxxxx:server-certificate/test_cert" # Replace with your certificate ARN

  default_action {
    type = "forward"
 target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

resource "aws_lb_target_group" "wordpress_tg" {
 name = "${var.project_name}-tg"
  port = 80
 protocol = "HTTP"
 vpc_id = aws_vpc.main.id

 health_check {
    path = "/"
  }
}


# S3 Bucket

resource "aws_s3_bucket" "wordpress_static_assets" {
 bucket = "${var.project_name}-static-assets"
 acl   = "private"

 tags = {
    Name = "${var.project_name}-s3-bucket"
    Environment = var.environment
    Project = var.project_name
  }
}


# Cloudfront


# Route53 (example)


# Outputs
output "alb_dns_name" {
 value = aws_lb.wordpress_alb.dns_name
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}


