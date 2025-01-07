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
  description = "The AWS region to deploy resources in"
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
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

variable "allowed_ssh_ips" {
  description = "IP addresses allowed to SSH into the bastion host"
  default     = ["0.0.0.0/0"]
}

variable "allowed_http_ips" {
  description = "IP addresses allowed to access the web servers"
  default     = ["0.0.0.0/0"]
}

variable "db_instance_type" {
  description = "Instance type for RDS"
  default     = "db.t2.small"
}

variable "db_engine" {
  description = "Database engine for RDS"
  default     = "mysql"
}

variable "ami_id" {
  description = "AMI ID for EC2 instances"
  default     = "ami-0abcdef1234567890"
}

resource "aws_vpc" "wordpress" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "wordpress-vpc"
  }
}

resource "aws_internet_gateway" "wordpress" {
  vpc_id = aws_vpc.wordpress.id
  tags = {
    Name = "wordpress-igw"
  }
}

resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name = "wordpress-public-subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "wordpress-private-subnet-${count.index + 1}"
  }
}

resource "aws_security_group" "web_server" {
  vpc_id = aws_vpc.wordpress.id
  description = "Allow HTTP, HTTPS, and SSH traffic"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_ips
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_ips
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_ips
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress-web-sg"
  }
}

resource "aws_security_group" "database" {
  vpc_id = aws_vpc.wordpress.id
  description = "Allow MySQL traffic from web server group"

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.web_server.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress-db-sg"
  }
}

resource "aws_instance" "bastion" {
  ami           = var.ami_id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public[0].id
  key_name      = "bastion-key"

  security_groups = [aws_security_group.web_server.name]

  associate_public_ip_address = true

  tags = {
    Name = "wordpress-bastion-host"
  }
}

resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
}

resource "aws_efs_file_system" "wordpress" {
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  performance_mode = "generalPurpose"
  tags = {
    Name = "wordpress-efs"
  }
}

resource "aws_efs_mount_target" "wordpress" {
  count          = length(var.private_subnet_cidrs)
  file_system_id = aws_efs_file_system.wordpress.id
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  security_groups = [aws_security_group.web_server.id]
}

resource "aws_elasticache_subnet_group" "wordpress" {
  name       = "wordpress-elasticache-subnet-group"
  subnet_ids = aws_subnet.private.*.id
}

resource "aws_elasticache_cluster" "wordpress" {
  cluster_id           = "wordpress-cache"
  engine               = "redis"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  subnet_group_name    = aws_elasticache_subnet_group.wordpress.name
  security_group_ids   = [aws_security_group.web_server.id]
  parameter_group_name = "default.redis3.2"
}

resource "aws_lb" "wordpress" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_server.id]
  subnets            = aws_subnet.public.*.id

  tags = {
    Name = "wordpress-alb"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = 443
  protocol          = "HTTPS"

  ssl_policy = "ELBSecurityPolicy-2016-08"
  certificate_arn = var.ssl_certificate_arn

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}

resource "aws_lb_target_group" "wordpress" {
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "wordpress-tg"
  }
}

resource "aws_autoscaling_group" "wordpress" {
  launch_configuration = aws_launch_configuration.wordpress.id
  min_size             = 1
  max_size             = 3
  desired_capacity     = 1
  vpc_zone_identifier  = aws_subnet.private.*.id
  target_group_arns    = [aws_lb_target_group.wordpress.arn]

  tags = [
    {
      key                 = "Name"
      value               = "wordpress-asg"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress" {
  name          = "wordpress-lc"
  image_id      = var.ami_id
  instance_type = "t2.micro"
  security_groups = [aws_security_group.web_server.id]

  user_data = <<-EOF
              #!/bin/bash
              yum install -y httpd php php-mysql
              amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2
              systemctl start httpd
              systemctl enable httpd
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "wordpress" {
  identifier        = "wordpress-db"
  engine            = var.db_engine
  instance_class    = var.db_instance_type
  allocated_storage = 20
  name              = "wordpressdb"
  username          = "admin"
  password          = "password"
  vpc_security_group_ids = [aws_security_group.database.id]
  multi_az          = true
  skip_final_snapshot = true

  tags = {
    Name = "wordpress-db"
  }
}

resource "aws_s3_bucket" "wordpress" {
  bucket = "wordpress-static-assets-${random_id.bucket_id.hex}"
  acl    = "public-read"

  tags = {
    Name = "wordpress-static-assets"
  }
}

resource "random_id" "bucket_id" {
  byte_length = 8
}

resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_s3_bucket.wordpress.bucket_regional_domain_name
    origin_id   = "S3-wordpress-static-assets"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "WordPress CloudFront distribution"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-wordpress-static-assets"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "wordpress-cloudfront"
  }
}

resource "aws_route53_zone" "wordpress" {
  name = "example.com"
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = "www.example.com"
  type    = "A"
  alias {
    name                   = aws_lb.wordpress.dns_name
    zone_id                = aws_lb.wordpress.zone_id
    evaluate_target_health = true
  }
}

output "vpc_id" {
  value = aws_vpc.wordpress.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "elb_dns_name" {
  value = aws_lb.wordpress.dns_name
}

output "db_instance_endpoint" {
  value = aws_db_instance.wordpress.endpoint
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress.domain_name
}
