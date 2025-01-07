terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy resources in."
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "The CIDR block for the public subnet."
  default     = ["10.0.1.0/24"]
}

variable "private_subnet_cidr" {
  description = "The CIDR block for the private subnet."
  default     = ["10.0.2.0/24"]
}

variable "key_name" {
  description = "Key pair name for EC2 instances SSH access."
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_subnet" "public_subnet" {
  count             = length(var.public_subnet_cidr)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = element(var.public_subnet_cidr, count.index)
  map_public_ip_on_launch = true
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
}

resource "aws_subnet" "private_subnet" {
  count             = length(var.private_subnet_cidr)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = element(var.private_subnet_cidr, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
}

data "aws_availability_zones" "available" {}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name = "WordPressIGW"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table_association" "public_association" {
  count          = length(aws_subnet.public_subnet)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_server_sg" {
  name        = "web-server-sg"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS"
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
    Name = "WebServerSG"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "Allow MySQL access from web server SG"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "RDS_SG"
  }
}

resource "aws_instance" "bastion_host" {
  ami                    = data.aws_ami.amazon_linux.image_id
  instance_type          = "t2.micro"
  key_name               = var.key_name
  subnet_id              = aws_subnet.public_subnet[0].id
  associate_public_ip_address = true

  vpc_security_group_ids = [aws_security_group.web_server_sg.id]

  tags = {
    Name = "BastionHost"
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

resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion_host.id
  vpc      = true
}

resource "aws_efs_file_system" "wordpress_efs" {
  encrypted = true

  tags = {
    Name = "WordPressEFS"
  }
}

resource "aws_efs_mount_target" "efs_mount_target" {
  count          = length(aws_subnet.private_subnet)
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = aws_subnet.private_subnet[count.index].id

  security_groups = [aws_security_group.web_server_sg.id]
}

resource "aws_rds_cluster" "wordpress_db" {
  engine             = "aurora-mysql"
  engine_mode        = "serverless"
  availability_zones = data.aws_availability_zones.available.names
  database_name      = "wordpress"

  scaling_configuration {
    auto_pause = true
    min_capacity = 1
    max_capacity = 2
  }

  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  
  tags = {
    Name = "WordPressRDS"
  }
}

resource "aws_elb" "wordpress_elb" {
  listeners {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  availability_zones = data.aws_availability_zones.available.names
  security_groups    = [aws_security_group.web_server_sg.id]

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "WordPressELB"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  launch_configuration = aws_launch_configuration.wordpress_lc.id
  max_size             = 5
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.public_subnet[*].id

  tags = [
    {
      key                 = "Name"
      value               = "WordPressInstance"
      propagate_at_launch = true
    },
  ]
}

resource "aws_launch_configuration" "wordpress_lc" {
  image_id        = data.aws_ami.amazon_linux.image_id
  instance_type   = "t2.micro"
  key_name        = var.key_name

  user_data = <<-EOT
              #!/bin/bash
              yum update -y
              yum install -y httpd php mysql
              systemctl start httpd
              systemctl enable httpd
              EOT

  security_groups = [aws_security_group.web_server_sg.id]
}

resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "wordpress-assets"
  }

  default_cache_behavior {
    target_origin_id       = "wordpress-assets"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  enabled = true

  tags = {
    Name = "WordPressCF"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket_prefix = "wordpress-assets-"

  tags = {
    Name = "WordPressAssets"
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id                = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = true
  }
}

variable "domain_name" {
  description = "The domain name for WordPress."
}
