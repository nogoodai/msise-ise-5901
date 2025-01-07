# Terraform provider configuration
terraform {
  required_version = ">= 1.2.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.1.0"
    }
  }
}

# AWS provider configuration
provider "aws" {
  region = "us-west-2"
}

# Variables
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnets" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  type    = list(string)
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "db_instance_class" {
  type    = string
  default = "db.t2.micro"
}

variable "ec2_instance_type" {
  type    = string
  default = "t2.micro"
}

variable "ami_id" {
  type    = string
  default = "ami-abcd1234"
}

variable "domain_name" {
  type    = string
  default = "example.com"
}

# VPC and networking resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPress-VPC"
    Environment = "production"
  }
}

resource "aws_subnet" "public_subnets" {
  count = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnets[count.index]
  availability_zone = "${aws_vpc.wordpress_vpc.region}a"
  tags = {
    Name        = "Public-Subnet-${count.index}"
    Environment = "production"
  }
}

resource "aws_subnet" "private_subnets" {
  count = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = "${aws_vpc.wordpress_vpc.region}a"
  tags = {
    Name        = "Private-Subnet-${count.index}"
    Environment = "production"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "IGW"
    Environment = "production"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "Public-Route-Table"
    Environment = "production"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "Private-Route-Table"
    Environment = "production"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  count          = 2
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_assoc" {
  count          = 2
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security groups
resource "aws_security_group" "ec2_sg" {
  name        = "EC2-SG"
  description = "Allow inbound traffic on port 80 and 443"
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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "EC2-SG"
    Environment = "production"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "RDS-SG"
  description = "Allow inbound traffic on port 3306 from EC2 SG"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "RDS-SG"
    Environment = "production"
  }
}

# RDS instance
resource "aws_db_instance" "wordpress_db" {
  instance_class = var.db_instance_class
  engine         = "mysql"
  username       = "wordpressuser"
  password       = "wordpresspassword"
  db_name        = "wordpressdb"
  allocated_storage = 20
  storage_type = "gp2"
  publicly_accessible = true
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  availability_zone = "${aws_vpc.wordpress_vpc.region}a"
  tags = {
    Name        = "WordPress-DB"
    Environment = "production"
  }
}

# EC2 instance
resource "aws_instance" "wordpress_ec2" {
  ami           = var.ami_id
  instance_type = var.ec2_instance_type
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id = aws_subnet.public_subnets[0].id
  key_name = "wordpress-key"
  tags = {
    Name        = "WordPress-EC2"
    Environment = "production"
  }
}

# Elastic Load Balancer
resource "aws_alb" "wordpress_alb" {
  name            = "WordPress-ALB"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.ec2_sg.id]
  tags = {
    Name        = "WordPress-ALB"
    Environment = "production"
  }
}

resource "aws_alb_target_group" "wordpress_tg" {
  name     = "WordPress-TG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPress-TG"
    Environment = "production"
  }
}

resource "aws_alb_listener" "wordpress_listener" {
  load_balancer_arn = aws_alb.wordpress_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.wordpress_tg.arn
    type             = "forward"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPress-ASG"
  max_size                  = 5
  min_size                  = 1
  health_check_type        = "EC2"
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id
  launch_template {
    id      = aws_launch_template.wordpress_lt.id
    version = "$Latest"
  }
  tags = [
    {
      key                 = "Name"
      value               = "WordPress-ASG"
      propagate_at_launch = true
    },
  ]
}

resource "aws_launch_template" "wordpress_lt" {
  name          = "WordPress-LT"
  image_id      = var.ami_id
  instance_type = var.ec2_instance_type
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name = "wordpress-key"
  tags = {
    Name        = "WordPress-LT"
    Environment = "production"
  }
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = "S3Origin"
    custom_origin_config {
      http_port                = 80
      https_port              = 443
      origin_protocol_policy   = "match-viewer"
      origin_ssl_protocols     = ["SSLv3", "TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"

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

  tags = {
    Name        = "WordPress-CF"
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# S3 bucket
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = "wordpress-bucket"
  acl    = "private"

  tags = {
    Name        = "WordPress-S3-Bucket"
    Environment = "production"
  }
}

# Route 53 DNS configuration
resource "aws_route53_record" "wordpress_dns_record" {
  zone_id = aws_route53_zone.wordpress_dns_zone.id
  name    = "wordpress.${aws_route53_zone.wordpress_dns_zone.name}"
  type    = "A"

  alias {
    name                   = aws_alb.wordpress_alb.dns_name
    zone_id               = aws_alb.wordpress_alb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "wordpress_dns_zone" {
  name = var.domain_name
}

output "wordpress_alb_dns_name" {
  value = aws_alb.wordpress_alb.dns_name
}

output "wordpress_cf_distribution_id" {
  value = aws_cloudfront_distribution.wordpress_cf.id
}

output "wordpress_cf_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cf.domain_name
}

output "wordpress_s3_bucket_arn" {
  value = aws_s3_bucket.wordpress_s3_bucket.arn
}

output "wordpress_s3_bucket_id" {
  value = aws_s3_bucket.wordpress_s3_bucket.id
}

output "wordpress_dns_zone_name" {
  value = aws_route53_zone.wordpress_dns_zone.name
}

output "wordpress_dns_zone_id" {
  value = aws_route53_zone.wordpress_dns_zone.id
}
