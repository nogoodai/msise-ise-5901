terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = "us-east-1"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "admin_ips" {
  description = "Allowed IPs for administrative access via SSH"
  default     = ["0.0.0.0/0"]
}

variable "instance_type" {
  description = "EC2 instance type for WordPress"
  default     = "t2.micro"
}

variable "db_instance_class" {
  description = "RDS instance class for WordPress database"
  default     = "db.t2.small"
}

variable "ami_id" {
  description = "AMI ID for EC2 instances"
  default     = "ami-0c55b159cbfafe1f0"  # Example AMI (Amazon Linux 2)
}

variable "key_pair" {
  description = "SSH key pair name"
  default     = "my-key-pair"
}

variable "project_tag" {
  description = "Tag for the project"
  default     = "WordPressProject"
}

resource "aws_vpc" "wordpress" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "Production"
    Project     = var.project_tag
  }
}

resource "aws_internet_gateway" "wordpress" {
  vpc_id = aws_vpc.wordpress.id
  tags = {
    Name        = "WordPressIGW"
    Project     = var.project_tag
  }
}

resource "aws_subnet" "wordpress_public" {
  count                   = 2
  vpc_id                  = aws_vpc.wordpress.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "WordPressPublicSubnet-${count.index}"
    Project     = var.project_tag
  }
}

resource "aws_subnet" "wordpress_private" {
  count                   = 2
  vpc_id                  = aws_vpc.wordpress.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "WordPressPrivateSubnet-${count.index}"
    Project     = var.project_tag
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress.id
  tags = {
    Name        = "WordPressPublicRouteTable"
    Project     = var.project_tag
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress.id
}

resource "aws_route_table_association" "public_association" {
  count = 2
  subnet_id      = aws_subnet.wordpress_public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_server_sg" {
  vpc_id = aws_vpc.wordpress.id

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
    cidr_blocks = var.admin_ips
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WebServerSG"
    Project     = var.project_tag
  }
}

resource "aws_security_group" "database_sg" {
  vpc_id = aws_vpc.wordpress.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "DatabaseSG"
    Project     = var.project_tag
  }
}

resource "aws_instance" "bastion" {
  ami                  = var.ami_id
  instance_type        = var.instance_type
  subnet_id            = aws_subnet.wordpress_public[0].id
  key_name             = var.key_pair
  associate_public_ip_address = true

  vpc_security_group_ids = [aws_security_group.web_server_sg.id]

  tags = {
    Name        = "BastionHost"
    Project     = var.project_tag
  }
}

resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  tags = {
    Name        = "BastionEIP"
    Project     = var.project_tag
  }
}

resource "aws_efs_file_system" "wordpress" {
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  tags = {
    Name        = "WordPressEFS"
    Project     = var.project_tag
  }
}

resource "aws_efs_mount_target" "wordpress" {
  count          = 2
  file_system_id = aws_efs_file_system.wordpress.id
  subnet_id      = element(aws_subnet.wordpress_private.*.id, count.index)
}

resource "aws_db_instance" "wordpress" {
  allocated_storage    = 20
  db_name              = "wordpress"
  engine               = "mysql"
  instance_class       = var.db_instance_class
  username             = "admin"
  password             = "password123"
  multi_az             = true
  publicly_accessible  = false
  vpc_security_group_ids = [aws_security_group.database_sg.id]

  tags = {
    Name        = "WordPressRDS"
    Project     = var.project_tag
  }
}

resource "aws_elb" "wordpress" {
  name               = "wordpress-elb"
  availability_zones = data.aws_availability_zones.available.names
  security_groups    = [aws_security_group.web_server_sg.id]

  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }
}

resource "aws_autoscaling_group" "wordpress" {
  availability_zones        = data.aws_availability_zones.available.names
  desired_capacity          = 2
  max_size                  = 3
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  vpc_zone_identifier       = aws_subnet.wordpress_private.*.id
  launch_configuration      = aws_launch_configuration.wordpress.id
  target_group_arns         = [aws_elb.wordpress.arn]

  tag {
    key                 = "Name"
    value               = "WordPressAutoScaling"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress" {
  image_id                   = var.ami_id
  instance_type              = var.instance_type
  security_groups            = [aws_security_group.web_server_sg.id]
  key_name                   = var.key_pair
  associate_public_ip_address = true

  user_data = <<-EOS
                #!/bin/bash
                yum update -y
                yum install -y httpd php php-mysqlnd
                systemctl enable httpd
                systemctl start httpd
                echo "<?php phpinfo(); ?>" > /var/www/html/index.php
                EOS

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_s3_bucket.wordpress.bucket_domain_name
    origin_id   = "S3-WordPress"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    target_origin_id       = "S3-WordPress"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_All"

  tags = {
    Name        = "WordPressCloudFront"
    Project     = var.project_tag
  }
}

resource "aws_s3_bucket" "wordpress" {
  bucket = "wordpress-static-assets"

  tags = {
    Name        = "WordPressS3Bucket"
    Project     = var.project_tag
  }
}

resource "aws_route53_zone" "wordpress" {
  name = "mywordpresssite.com"

  tags = {
    Name        = "WordPressRoute53Zone"
    Project     = var.project_tag
  }
}

resource "aws_route53_record" "wordpress" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = "www.mywordpresssite.com"
  type    = "A"
  alias {
    name                   = aws_elb.wordpress.dns_name
    zone_id                = aws_elb.wordpress.zone_id
    evaluate_target_health = true
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}
