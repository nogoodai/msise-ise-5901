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

variable "rds_instance_class" {
  type    = string
  default = "db.t3.micro"
}


resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name = "WordPress-IGW"
  }
}


resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "WordPress-Public-Subnet-${count.index}"
  }
}


resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index + length(var.public_subnet_cidrs)]
  tags = {
    Name = "WordPress-Private-Subnet-${count.index}"
  }
}

data "aws_availability_zones" "available" {}



resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "WordPress-Public-Route-Table"
  }

}

resource "aws_route_table_association" "public_subnet_association" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}



resource "aws_security_group" "web_server_sg" {
  name        = "wordpress-web-sg"
  description = "Allow HTTP and HTTPS inbound"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

    ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
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
    Name = "wordpress-web-sg"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "wordpress-rds-sg"
  description = "Allow inbound traffic from web servers"
  vpc_id      = aws_vpc.wordpress_vpc.id


  ingress {
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]

  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  tags = {
    Name = "wordpress-rds-sg"
  }
}



resource "aws_db_instance" "default" {

  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class      = var.rds_instance_class
  name                 = "wordpress"
  username             = "admin" # Replace with your username
  password             = "password" # Replace with your password. Use random_password resource in production
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name  = aws_db_subnet_group.default.name


}


resource "aws_db_subnet_group" "default" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private_subnets[*].id

  tags = {
    Name = "MyDBSubnetGroup"
  }

}


resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${random_id.bucket_id.hex}"
  acl    = "private"


}


resource "random_id" "bucket_id" {
  byte_length = 8
}



data "aws_ami" "amazon_linux" {


  most_recent = true
  owners      = ["amazon"]


  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]

  }



}

resource "aws_launch_configuration" "wordpress_lc" {
  image_id            = data.aws_ami.amazon_linux.id
  instance_type        = var.instance_type
  security_groups      = [aws_security_group.web_server_sg.id]


  user_data = <<-EOF
#!/bin/bash
yum update -y
yum install httpd php php-mysqlnd -y
systemctl start httpd
systemctl enable httpd
echo "<?php phpinfo(); ?>" > /var/www/html/index.php
EOF


}



resource "aws_lb" "wordpress_alb" {


  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_server_sg.id]
  subnets            = aws_subnet.public_subnets[*].id


}



resource "aws_lb_target_group" "wordpress_tg" {
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id


  health_check {
    path                = "/"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }

}

resource "aws_lb_listener" "http" {

  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn

  }
}


resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  min_size                  = 2
  max_size                  = 4

  vpc_zone_identifiers      = aws_subnet.private_subnets[*].id
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  target_group_arns         = [aws_lb_target_group.wordpress_tg.arn]
  health_check_grace_period = 60
  health_check_type         = "ELB"

}


resource "aws_cloudfront_distribution" "wordpress_cdn" {

  origin {

    domain_name = aws_lb.wordpress_alb.dns_name
    origin_id   = "wordpress-alb"


    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"


      origin_ssl_protocols = ["TLSv1.2"]
    }

  }



  enabled             = true
  is_ipv6_enabled     = true

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-alb"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      cookies      = "none"
      query_string = false



    }




  }


  price_class = "PriceClass_All"

  viewer_certificate {
    cloudfront_default_certificate = true

  }
}


resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com" # Replace with your domain
}



output "alb_dns_name" {
  value = aws_lb.wordpress_alb.dns_name
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cdn.domain_name
}
