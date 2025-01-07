provider "aws" {
  region = "us-west-2"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type = list(string)
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  type = list(string)
  default = ["us-west-2a", "us-west-2b"]
}

variable "instance_type" {
  default = "t2.micro"
}

variable "ami_id" {
  default = "ami-0c55b159cbfafe1f0"
}

variable "key_pair_name" {
  default = "wordpress-key"
}

variable "rds_instance_class" {
  default = "db.t2.small"
}

variable "rds_engine" {
  default = "mysql"
}

variable "efs_performance_mode" {
  default = "generalPurpose"
}

variable "cloudfront_ssl_certificate_arn" {
  default = "arn:aws:iam::123456789012:server-certificate/cloudfront-ssl-certificate"
}

variable "route53_zone_name" {
  default = "example.com"
}

# VPC and networking resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnet_cidrs)
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PublicSubnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PrivateSubnet-${count.index + 1}"
  }
}

resource "aws_route_table_association" "public_route_table_associations" {
  count = length(var.public_subnet_cidrs)
  subnet_id = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_route_table_associations" {
  count = length(var.private_subnet_cidrs)
  subnet_id = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security groups
resource "aws_security_group" "wordpress_sg" {
  name        = "WordPressSG"
  description = "Security group for WordPress instances"
  vpc_id      = aws_vpc.wordpress_vpc.id

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
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "RDSSG"
  description = "Security group for RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 instances
resource "aws_instance" "wordpress_instance" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.public_subnets[0].id

  tags = {
    Name = "WordPressInstance"
  }
}

# RDS instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = var.rds_engine
  engine_version       = "8.0.20"
  instance_class       = var.rds_instance_class
  name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = "wordpresspassword"
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot  = true
  multi_az             = true
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress_db_subnet_group"
  subnet_ids = aws_subnet.private_subnets.*.id

  tags = {
    Name = "WordPressDBSubnetGroup"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_sg.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  listener {
    instance_port      = 443
    instance_protocol = "https"
    lb_port           = 443
    lb_protocol       = "https"
    ssl_certificate_id = var.cloudfront_ssl_certificate_arn
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 30
  }

  cross_zone_load_balancing = true
  idle_timeout                = 400
  connection_draining        = true
  connection_draining_timeout = 400

  tags = {
    Name = "WordPressELB"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 1
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id

  tag {
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.wordpress_sg.id]
  key_name               = var.key_pair_name
  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              sudo apt-get install -y apache2
              sudo service apache2 start
              EOF
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }

  enabled = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-elb"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = var.cloudfront_ssl_certificate_arn
    ssl_support_method  = "sni-only"
  }
}

# S3 bucket
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = "wordpress-s3-bucket"
  acl    = "private"

  tags = {
    Name = "WordPressS3Bucket"
  }
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_route53_zone" {
  name = var.route53_zone_name
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name    = var.route53_zone_name
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id                = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cfd.domain_name
}
