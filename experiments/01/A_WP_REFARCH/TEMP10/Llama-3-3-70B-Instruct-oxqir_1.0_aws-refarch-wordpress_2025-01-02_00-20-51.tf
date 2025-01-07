# Provider configuration for AWS
provider "aws" {
  region                  = "us-west-2"
  shared_credentials_file = "~/.aws/credentials"
  profile                 = "default"
}

# Define variables
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}
variable "vpc_name" {
  default = "wordpress-vpc"
}
variable "public_subnets" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}
variable "private_subnets" {
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}
variable "instance_type" {
  default = "t2.micro"
}
variable "ami_id" {
  default = "ami-0c94855ba95c71c99"
}
variable "db_instance_class" {
  default = "db.t2.small"
}
variable "db_username" {
  default = "wordpress"
}
variable "db_password" {
  default = "password123"
}
variable "cloudfront_ssl_cert" {
  default = "arn:aws:iam::123456789012:certificate/ certificate-id"
}
variable "domain_name" {
  default = "example.com"
}

# VPC and networking resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = var.vpc_name
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "wordpress-igw"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "private-route-table"
  }
}

resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnets)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnets[count.index]
  availability_zone = "us-west-2${count.index + 1}"
  tags = {
    Name = "public-subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnets)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = "us-west-2${count.index + 1}"
  tags = {
    Name = "private-subnet-${count.index + 1}"
  }
}

resource "aws_route_table_association" "public_route_association" {
  count = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_route_association" {
  count = length(aws_subnet.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security groups
resource "aws_security_group" "wordpress_sg" {
  name        = "wordpress-sg"
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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Security group for RDS instances"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
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
resource "aws_instance" "wordpress_instances" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.wordpress_sg.id
  ]
  key_name               = "wordpress-key"
  subnet_id              = aws_subnet.public_subnets[0].id
  user_data              = file("wordpress-install.sh")
  tags = {
    Name = "wordpress-instance"
  }
}

# RDS instance
resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 10
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = var.db_instance_class
  name                 = "wordpressdb"
  username             = var.db_username
  password             = var.db_password
  parameter_group_name = "default.mysql5.7"
  db_subnet_group_name = "wordpress-dbsubnetgroup"
  vpc_security_group_ids = [
    aws_security_group.rds_sg.id
  ]
  skip_final_snapshot  = true
}

# Elastic Load Balancer
resource "aws_alb" "wordpress_alb" {
  name            = "wordpress-alb"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_sg.id]
}

resource "aws_alb_target_group" "wordpress_tg" {
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
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
  name                      = "wordpress-asg"
  max_size                  = 5
  min_size                  = 1
  desired_capacity          = 1
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id
  launch_template {
    id      = aws_launch_template.wordpress_lt.id
    version = "$Latest"
  }
  tag {
    key                 = "Name"
    value               = "wordpress-instance"
    propagate_at_launch = true
  }
}

resource "aws_launch_template" "wordpress_lt" {
  name          = "wordpress-lt"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name               = "wordpress-key"
  user_data              = file("wordpress-install.sh")
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = "wordpress-origin"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases = ["www.${var.domain_name}", var.domain_name]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-origin"

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
    acm_certificate_arn = var.cloudfront_ssl_cert
    ssl_support_method  = "sni-only"
  }
}

# S3 bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = var.domain_name
  acl    = "public-read"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource = [
          aws_s3_bucket.wordpress_bucket.arn,
          "${aws_s3_bucket.wordpress_bucket.arn}/*",
        ]
      },
    ]
  })

  website {
    index_document = "index.html"
  }
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_alb.wordpress_alb.dns_name
    zone_id               = aws_alb.wordpress_alb.zone_id
    evaluate_target_health = false
  }
}

output "alb_dns_name" {
  value = aws_alb.wordpress_alb.dns_name
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.wordpress_cfd.id
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_bucket.id
}

output "route53_zone_id" {
  value = aws_route53_zone.wordpress_zone.id
}
