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

resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project_name}-public-subnet-a"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  tags = {
    Name        = "${var.project_name}-public-subnet-b"
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

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}


resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}



data "aws_availability_zones" "available" {}

# Security Groups



resource "aws_security_group" "web_sg" {
 name        = "${var.project_name}-web-sg"
  description = "Allow inbound HTTP and HTTPS"
  vpc_id      = aws_vpc.main.id

 ingress {
    description      = "HTTP from anywhere"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "HTTPS from anywhere"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }


  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name        = "${var.project_name}-allow-http-https-sg"
    Environment = var.environment
    Project     = var.project_name

  }
}



# EC2 Instances and Autoscaling


resource "aws_instance" "web_server" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_a.id # Or a private subnet if you are using a load balancer
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  associate_public_ip_address = true # Set to false if in a private subnet

  user_data = <<-EOF
#!/bin/bash
yum update -y
yum install httpd -y
systemctl start httpd
systemctl enable httpd
echo "Hello World from $(hostname -f)" > /var/www/html/index.html
  EOF




  tags = {
    Name        = "${var.project_name}-web-server"
    Environment = var.environment
    Project     = var.project_name

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




# RDS Instance


resource "aws_db_subnet_group" "default" {
 subnet_ids = [aws_subnet.public_a.id, aws_subnet.public_b.id] # Replace with your subnet IDs

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
    Project     = var.project_name

  }
}

resource "aws_db_instance" "default" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t2.micro"
  name                 = "wordpress"
  username             = "admin" # Replace with your username
  password             = "password123"  # Replace with a strong password
  db_subnet_group_name = aws_db_subnet_group.default.name
  skip_final_snapshot  = true

  tags = {
    Name        = "${var.project_name}-db-instance"
    Environment = var.environment
    Project     = var.project_name

  }
}




# Elastic Load Balancer




resource "aws_lb" "example" {
  internal           = false
  load_balancer_type = "application"
  name               = "${var.project_name}-lb"
  security_groups    = [aws_security_group.web_sg.id] # Replace with your security group IDs
 subnets             = [aws_subnet.public_a.id, aws_subnet.public_b.id]



 tags = {
    Name        = "${var.project_name}-elb"
    Environment = var.environment
    Project     = var.project_name

  }


}

resource "aws_lb_target_group" "example" {
  name     = "${var.project_name}-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id


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

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = "80"
  protocol          = "HTTP"



  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.example.arn
  }
}



# S3 Bucket



resource "aws_s3_bucket" "example" {
  bucket = "${var.project_name}-s3-bucket"

  tags = {
    Name        = "${var.project_name}-s3-bucket"
    Environment = var.environment
    Project     = var.project_name

  }
}



# Route 53 (Basic Example - Requires a hosted zone)

# resource "aws_route53_record" "example" {
#   zone_id = "YOUR_HOSTED_ZONE_ID"  # Replace with your hosted zone ID
#   name    = "example.com"         # Replace with your domain name
#   type    = "A"
#   alias {
#     name                   = aws_lb.example.dns_name
#     zone_id                = aws_lb.example.zone_id
#     evaluate_target_health = true
#   }
# }




# Output



output "lb_dns_name" {
  value = aws_lb.example.dns_name
}

output "s3_bucket_name" {
 value = aws_s3_bucket.example.bucket
}

# output "cloudfront_distribution_domain_name" {
#  value = aws_cloudfront_distribution.example.domain_name # If using CloudFront
# }


output "rds_endpoint" {
 value = aws_db_instance.default.address
}

