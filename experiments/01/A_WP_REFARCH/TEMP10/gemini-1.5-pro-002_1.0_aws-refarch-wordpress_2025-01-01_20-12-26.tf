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

variable "environment" {
  type    = string
  default = "dev"
}

variable "project" {
  type    = string
  default = "wordpress"
}

# VPC and Networking
resource "aws_vpc" "wordpress-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "wordpress-vpc"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "public-subnet-a" {
  vpc_id            = aws_vpc.wordpress-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "public-subnet-a"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "private-subnet-a" {
  vpc_id            = aws_vpc.wordpress-vpc.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "private-subnet-a"
    Environment = var.environment
    Project     = var.project
  }
}



data "aws_availability_zones" "available" {}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.wordpress-vpc.id
  tags = {
    Name        = "wordpress-igw"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table" "public-route-table" {
  vpc_id = aws_vpc.wordpress-vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name        = "public-route-table"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table_association" "public-subnet-association-a" {
  subnet_id      = aws_subnet.public-subnet-a.id
  route_table_id = aws_route_table.public-route-table.id
}



# Security Groups

resource "aws_security_group" "web-sg" {
  name        = "web-sg"
  description = "Allow HTTP, HTTPS and SSH inbound"
  vpc_id      = aws_vpc.wordpress-vpc.id

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
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name        = "web-sg"
    Environment = var.environment
    Project     = var.project
  }
}


resource "aws_security_group" "rds-sg" {
  name        = "rds-sg"
  description = "Allow inbound traffic from web servers"
  vpc_id      = aws_vpc.wordpress-vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web-sg.id]
  }
  tags = {
    Name        = "rds-sg"
    Environment = var.environment
    Project     = var.project
  }

}



# EC2, RDS, ALB, Autoscaling

resource "aws_instance" "web-server" {


  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"


  subnet_id              = aws_subnet.public-subnet-a.id
  vpc_security_group_ids = [aws_security_group.web-sg.id]
  user_data              = file("user_data.sh") # Placeholder for user data

  tags = {
    Name        = "web-server"
    Environment = var.environment
    Project     = var.project

  }
}


data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}


resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t2.micro"
  name                 = "wordpress_db"
  username             = "admin" # Replace with a secure generated password
  password             = "password" # Replace with a secure generated password
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true
  vpc_security_group_ids = [aws_security_group.rds-sg.id]
  db_subnet_group_name  = aws_db_subnet_group.default.name

  tags = {
    Name        = "wordpress-db"
    Environment = var.environment
    Project     = var.project
  }
}


resource "aws_db_subnet_group" "default" {

 name       = "wordpress-db-subnet-group"
 subnet_ids = [aws_subnet.private-subnet-a.id]
  tags = {
    Name        = "wordpress-db-subnet-group"
    Environment = var.environment
    Project     = var.project
  }
}


resource "aws_elb" "wordpress_elb" {
  # More attributes available below. For now, just name and availability zones.


  name            = "wordpress-elb"
  subnets         = [aws_subnet.public-subnet-a.id]
  security_groups = [aws_security_group.web-sg.id]


  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port             = 80
    lb_protocol         = "http"
  }


  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 30
  }


  tags = {
    Name        = "wordpress-elb"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_autoscaling_group" "web-asg" {
  name                 = "web-asg"

  min_size             = 1
  max_size             = 2
  vpc_zone_identifier  = [aws_subnet.public-subnet-a.id]
  launch_configuration = aws_launch_configuration.web_launch_config.name
  load_balancers       = [aws_elb.wordpress_elb.name]
  target_group_arns    = [aws_lb_target_group.web-tg.arn] # Target group needed

  tag {
    key                 = "Name"
    value               = "web-asg"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project
    propagate_at_launch = true
  }

}

resource "aws_launch_configuration" "web_launch_config" {
  name_prefix          = "web-lc-"
  image_id             = data.aws_ami.amazon_linux.id
  instance_type        = "t2.micro"
  security_groups      = [aws_security_group.web-sg.id]
  user_data           = file("user_data.sh") # Needs to be created
  associate_public_ip_address = true


  lifecycle {
    create_before_destroy = true
  }

}


resource "aws_lb_target_group" "web-tg" {
 name        = "web-tg"
 port        = 80
 protocol    = "HTTP"
 target_type = "instance"
 vpc_id      = aws_vpc.wordpress-vpc.id

 health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }


}




# S3 and Cloudfront

resource "aws_s3_bucket" "static-assets" {
  bucket = "wordpress-static-assets-${var.environment}-${random_id.bucket_id.hex}"
  acl    = "private"


  tags = {
    Name        = "wordpress-static-assets"
    Environment = var.environment
    Project     = var.project
  }
}


resource "random_id" "bucket_id" {
  byte_length = 8
}



# Placeholder for CloudFront. Needs origin (S3 or ALB)
# resource "aws_cloudfront_distribution" "s3_distribution" {

# }



# Route 53 (Placeholder - requires domain name)
# resource "aws_route53_zone" "primary" {

# }





output "vpc_id" {
  value = aws_vpc.wordpress-vpc.id
}

output "elb_dns_name" {
 value = aws_elb.wordpress_elb.dns_name

}

output "s3_bucket_name" {
  value = aws_s3_bucket.static-assets.bucket

}


