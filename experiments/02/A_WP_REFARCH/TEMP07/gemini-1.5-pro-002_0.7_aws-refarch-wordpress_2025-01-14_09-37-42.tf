terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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

variable "tags" {
  type = map(string)
  default = {
    Environment = "production"
    Project     = "wordpress"
  }
}


# VPC and Networking
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "10.0.0.0/16"
  tags       = merge(var.tags, { Name = "wordpress-vpc" })
}

resource "aws_subnet" "public_subnet_a" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags             = merge(var.tags, { Name = "public-subnet-a" })
}

resource "aws_subnet" "public_subnet_b" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  tags             = merge(var.tags, { Name = "public-subnet-b" })
}

resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.101.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags             = merge(var.tags, { Name = "private-subnet-a" })
}


resource "aws_subnet" "private_subnet_b" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.102.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  tags             = merge(var.tags, { Name = "private-subnet-b" })
}

data "aws_availability_zones" "available" {}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags   = merge(var.tags, { Name = "wordpress-igw" })
}


resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }

  tags = merge(var.tags, { Name = "public-route-table" })
}


resource "aws_route_table_association" "public_subnet_a_association" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_b_association" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_route_table.id
}


# Security Groups

resource "aws_security_group" "web_server_sg" {
  name        = "web-server-sg"
  vpc_id      = aws_vpc.wordpress_vpc.id
  description = "Allow HTTP/HTTPS inbound"

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


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "web-server-security-group" })
}




resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Allow inbound traffic from web servers"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.tags, { Name = "rds-security-group" })
}


# EC2 and RDS

resource "aws_instance" "wordpress_instance" {


  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro" # Consider t2.micro or other suitable types.
  subnet_id = aws_subnet.public_subnet_a.id # Place in public subnet for ALB access

  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  user_data = <<-EOF
#!/bin/bash
yum update -y
yum install httpd php mysql php-mysql -y
systemctl start httpd
systemctl enable httpd
echo "<?php phpinfo(); ?>" > /var/www/html/index.php
EOF



  tags = merge(var.tags, { Name = "wordpress-instance" })
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
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                = "mysql"
  engine_version        = "8.0" # Or latest supported version.
  instance_class        = "db.t3.micro"
  name                  = "wordpress_db"
  username              = "wordpress_user" # Replace with secure credentials.
  password              = random_password.rds_password.result
  parameter_group_name  = "default.mysql8.0" # Use specific parameter group.
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true
  db_subnet_group_name  = aws_db_subnet_group.wordpress_db_subnet_group.name

  tags = merge(var.tags, { Name = "wordpress-db" })
}



resource "random_password" "rds_password" {
  length           = 16
  special          = true
  override_special = "!#$%&()*+,-./:;<=>?@[]^_{|}~"
}


resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]

  tags = merge(var.tags, { Name = "db-subnet-group" })
}


# Load Balancer

resource "aws_lb" "wordpress_lb" {
 name               = "wordpress-lb"
 internal           = false
 load_balancer_type = "application"
 security_groups    = [aws_security_group.web_server_sg.id]
 subnets            = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]

  tags = merge(var.tags, { Name = "wordpress-lb" })

}


resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress_lb.arn
  port              = "80"
  protocol          = "HTTP"


  default_action {
    type             = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.wordpress_lb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01" # Or a custom policy
  certificate_arn = "arn:aws:iam::xxxxxxxxxxxx:server-certificate/test_cert" # Replace with your certificate ARN


  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}


resource "aws_lb_target_group" "wordpress_tg" {
  name        = "wordpress-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.wordpress_vpc.id
  target_type = "instance"
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

resource "aws_lb_target_group_attachment" "wordpress_instance_attachment" {
  target_group_arn = aws_lb_target_group.wordpress_tg.arn
  target_id        = aws_instance.wordpress_instance.id
  port             = 80
}


# Autoscaling

resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  min_size                  = 1
  max_size                  = 3
  desired_capacity          = 1
  health_check_grace_period = 300
  health_check_type         = "ELB"
  default_cooldown          = 300
  force_delete              = true # Use with caution
  launch_template {
    id      = aws_launch_template.wordpress_lt.id
    version = "$Latest"
  }


  vpc_zone_identifier = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]


  tag {
    key                 = "Name"
    value               = "wordpress-asg"
    propagate_at_launch = true
  }
}


resource "aws_launch_template" "wordpress_lt" {


  name_prefix   = "wordpress-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web_server_sg.id]


  }
  user_data = base64encode(<<-EOF
#!/bin/bash
yum update -y
yum install httpd php mysql php-mysql -y
systemctl start httpd
systemctl enable httpd
echo "<?php phpinfo(); ?>" > /var/www/html/index.php
EOF
)

lifecycle {
    create_before_destroy = true
  }
}


# CloudFront and S3
resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${random_id.bucket_suffix.hex}"
  acl    = "private"


  tags = merge(var.tags, { Name = "wordpress-assets" })
}

resource "random_id" "bucket_suffix" {
  byte_length = 8
}

resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_lb.wordpress_lb.dns_name
    origin_id   = "wordpress-lb-origin"

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "http-only" # or match-viewer
      origin_ssl_protocols = ["TLSv1.2"]
    }

  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "WordPress CDN"
 price_class         = "PriceClass_100"


  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-lb-origin"
    viewer_protocol_policy = "redirect-to-https"
 min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }


  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}



# Route53 (Example - assumes a pre-existing hosted zone)
data "aws_route53_zone" "wordpress_zone" {
 name         = "example.com." # Replace with your domain.
 private_zone = false
}



resource "aws_route53_record" "wordpress_cdn_record" {
  zone_id = data.aws_route53_zone.wordpress_zone.zone_id
  name    = "cdn.example.com" # Replace with your subdomain.
  type    = "A"




  alias {
    name                   = aws_cloudfront_distribution.wordpress_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cdn.hosted_zone_id
    evaluate_target_health = false
  }
}



resource "aws_route53_record" "wordpress_lb_record" {
  zone_id = data.aws_route53_zone.wordpress_zone.zone_id
  name    = "www.example.com" #  Subdomain for the ALB.
  type    = "A"

  alias {
    name                   = aws_lb.wordpress_lb.dns_name
    zone_id                = aws_lb.wordpress_lb.zone_id
    evaluate_target_health = true
  }
}


output "cloudfront_domain" {
  value = aws_cloudfront_distribution.wordpress_cdn.domain_name
}

output "lb_dns_name" {
  value = aws_lb.wordpress_lb.dns_name
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_assets.bucket
}


