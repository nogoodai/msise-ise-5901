terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region  = var.region
  version = "5.1.0"
}

variable "region" {
  description = "AWS region to deploy the resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project Name for tagging resources"
  type        = string
  default     = "wordpress-project"
}

variable "environment" {
  description = "Environment for resources"
  type        = string
  default     = "production"
}

# VPC and Networking
resource "aws_vpc" "wordpress" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "WordPressVPC"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_internet_gateway" "wordpress" {
  vpc_id = aws_vpc.wordpress.id
  tags = {
    Name        = "wordpress-igw"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "wordpress_public" {
  count                   = 2
  vpc_id                  = aws_vpc.wordpress.id
  cidr_block              = cidrsubnet(aws_vpc.wordpress.cidr_block, 8, count.index)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name        = "wordpress-public-subnet-${count.index}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "wordpress_private" {
  count             = 2
  vpc_id            = aws_vpc.wordpress.id
  cidr_block        = cidrsubnet(aws_vpc.wordpress.cidr_block, 8, count.index + 100)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "wordpress-private-subnet-${count.index}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress.id
  tags = {
    Name        = "wordpress-public-route-table"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress.id
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = element(aws_subnet.wordpress_public.*.id, count.index)
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
    cidr_blocks = ["1.2.3.4/32"] # Placeholder for admin IP
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "wordpress-web-server-sg"
    Environment = var.environment
    Project     = var.project_name
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
  tags = {
    Name        = "wordpress-db-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_security_group" "elb_sg" {
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
  tags = {
    Name        = "wordpress-elb-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_instance" "bastion" {
  ami           = "ami-0123456789abcdef0" # Placeholder AMI
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.wordpress_public[0].id
  security_groups = [aws_security_group.web_server_sg.name]
  associate_public_ip_address = true
  key_name      = "wordpress-key"
  tags = {
    Name        = "wordpress-bastion"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  vpc_zone_identifier = aws_subnet.wordpress_private.*.id
  max_size            = 5
  min_size            = 1
  desired_capacity    = 2
  launch_configuration = aws_launch_configuration.wordpress_launch_config.id

  tag {
    key                 = "Name"
    value               = "wordpress-asg-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress_launch_config" {
  name          = "wordpress-launch-configuration"
  image_id      = "ami-0123456789abcdef0" # Placeholder AMI
  instance_type = "t2.micro"
  key_name      = "wordpress-key"
  security_groups = [aws_security_group.web_server_sg.id]

  user_data = <<EOF
#!/bin/bash
yum update -y
yum install -y httpd php php-mysql
chkconfig httpd on
service httpd start
EOF

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "wordpress-launch-configuration"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_alb" "wordpress_alb" {
  name               = "wordpress-alb"
  internal           = false
  security_groups    = [aws_security_group.elb_sg.id]
  subnets            = aws_subnet.wordpress_public.*.id
  load_balancer_type = "application"
  tags = {
    Name        = "wordpress-alb"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_alb_listener" "http" {
  load_balancer_arn = aws_alb.wordpress_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_alb_target_group.wordpress_tg.arn
  }
}

resource "aws_alb_listener" "https" {
  load_balancer_arn = aws_alb.wordpress_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:us-east-1:123456789012:certificate/abcdefg-1234"

  default_action {
    type = "forward"
    target_group_arn = aws_alb_target_group.wordpress_tg.arn
  }
}

resource "aws_alb_target_group" "wordpress_tg" {
  name     = "wordpress-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    protocol            = "HTTP"
  }

  tags = {
    Name        = "wordpress-target-group"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t2.small"
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password"
  parameter_group_name = "default.mysql8.0"
  publicly_accessible  = false
  multi_az             = true
  vpc_security_group_ids = [aws_security_group.database_sg.id]
  tags = {
    Name        = "wordpress-db-instance"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-static-assets-bucket"

  tags = {
    Name        = "wordpress-assets"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = "wordpress-alb-origin"
  }

  enabled               = true
  is_ipv6_enabled       = true
  default_root_object   = "index.html"
  comment               = "CloudFront Distribution for WordPress"
  default_cache_behavior {
    target_origin_id       = "wordpress-alb-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 300
    max_ttl                = 3600
  }

  tags = {
    Name        = "wordpress-cloudfront"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route53_record" "wordpress_alb" {
  zone_id = "Z1234567890"
  name    = "wordpress.${var.project_name}.com"
  type    = "A"

  alias {
    name                   = aws_alb.wordpress_alb.dns_name
    zone_id                = aws_alb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

data "aws_availability_zones" "available" {}
