terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy resources"
  default     = "us-west-2"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into EC2 instances"
  default     = "0.0.0.0/0"
}

variable "key_name" {
  description = "The key pair name for SSH access to EC2 instances"
  default     = "my-ssh-key"
}

variable "environment" {
  description = "The deployment environment"
  default     = "production"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name        = "wordpress-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.${count.index}.0/24"
  map_public_ip_on_launch = true
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name        = "public-subnet-${count.index}"
    Environment = var.environment
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.${count.index + 2}.0/24"
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name        = "private-subnet-${count.index}"
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "wordpress-igw"
    Environment = var.environment
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name        = "public-route-table"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id

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

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
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
  }
}

resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id

  ingress {
    description = "Allow MySQL access from web"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "rds-sg"
    Environment = var.environment
  }
}

resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  instance_class       = "db.t2.small"
  name                 = "wordpress"
  username             = "wpuser"
  password             = "wppassword"
  backup_retention_period = 7
  multi_az             = true
  storage_type         = "gp2"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet.name

  tags = {
    Name        = "wordpress-db"
    Environment = var.environment
  }
}

resource "aws_db_subnet_group" "wordpress_db_subnet" {
  name       = "wordpress-db-subnet"
  subnet_ids = aws_subnet.private.*.id

  tags = {
    Name        = "wordpress-db-subnet"
    Environment = var.environment
  }
}

resource "aws_launch_configuration" "wordpress_lc" {
  name_prefix          = "wordpress-lc-"
  image_id             = data.aws_ami.latest.id
  instance_type        = "t2.micro"
  key_name             = var.key_name
  security_groups      = [aws_security_group.web_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install -y php7.3
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              curl -O https://wordpress.org/latest.tar.gz
              tar -xzf latest.tar.gz
              cp -r wordpress/* /var/www/html/
              chown -R apache:apache /var/www/html/
              EOF
}

resource "aws_autoscaling_group" "wordpress_asg" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.public.*.id
  launch_configuration = aws_launch_configuration.wordpress_lc.name

  tags = [
    {
      key                 = "Name"
      value               = "wordpress-asg-instance"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = var.environment
      propagate_at_launch = true
    }
  ]
}

resource "aws_elb" "wordpress_elb" {
  name               = "wordpress-elb"
  availability_zones = data.aws_availability_zones.available.names

  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  listener {
    instance_port     = 443
    instance_protocol = "HTTPS"
    lb_port           = 443
    lb_protocol       = "HTTPS"
    ssl_certificate_id = var.ssl_certificate_arn
  }

  instances          = [aws_autoscaling_group.wordpress_asg.id]
  security_groups    = [aws_security_group.web_sg.id]

  tags = {
    Name        = "wordpress-elb"
    Environment = var.environment
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket_prefix = "wordpress-assets-"

  tags = {
    Name        = "wordpress-assets"
    Environment = var.environment
  }
}

resource "aws_cloudfront_distribution" "wordpress_cd" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_domain_name
    origin_id   = "S3-wordpress-assets"
  }

  enabled         = true
  is_ipv6_enabled = true
  default_cache_behavior {
    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    target_origin_id = "S3-wordpress-assets"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name        = "wordpress-cloudfront"
    Environment = var.environment
  }
}

resource "aws_route53_zone" "wordpress" {
  name = var.dns_zone_name

  tags = {
    Name        = "wordpress-dns-zone"
    Environment = var.environment
  }
}

resource "aws_route53_record" "wordpress" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = var.dns_record_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cd.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cd.hosted_zone_id
    evaluate_target_health = true
  }
}

data "aws_availability_zones" "available" {}

data "aws_ami" "latest" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

output "public_dns" {
  value = aws_route53_record.wordpress.fqdn
}
