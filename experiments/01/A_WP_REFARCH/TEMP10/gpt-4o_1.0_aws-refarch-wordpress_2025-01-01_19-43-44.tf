terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy resources."
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets."
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "allowed_ssh_ips" {
  description = "IP ranges allowed to SSH into bastion hosts and instances."
  type        = list(string)
  default     = ["0.0.0.0/0"] # Adjust for your specific needs
}

variable "environment" {
  description = "The environment for deployment (e.g., dev, staging, prod)."
  default     = "prod"
}

variable "instance_type" {
  description = "EC2 instance type for the WordPress servers."
  default     = "t2.micro"
}

variable "db_instance_type" {
  description = "RDS instance type."
  default     = "db.t2.small"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name       = "WordPressVPC"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name       = "WordPressIGW"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name       = "WordPressPublicSubnet-${count.index + 1}"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name       = "WordPressPrivateSubnet-${count.index + 1}"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name       = "WordPressPublicRouteTable"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id

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
    cidr_blocks = var.allowed_ssh_ips
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name       = "WordPressWebServerSG"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id

  ingress {
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
    Name       = "WordPressDBSG"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public[0].id
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  associate_public_ip_address = true

  tags = {
    Name       = "WordPressBastionHost"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_rds_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = var.db_instance_type
  name                 = "wordpressdb"
  username             = "admin"
  password             = "importantpassword"
  parameter_group_name = "default.mysql8.0"
  multi_az             = true
  publicly_accessible  = false
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  tags = {
    Name       = "WordPressRDS"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_launch_configuration" "wordpress" {
  name          = "WordPressLaunchConfig"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  key_name      = var.key_name

  security_groups = [aws_security_group.web_sg.id]
  
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install php7.4 -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              # Additional WordPress installation commands
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  launch_configuration = aws_launch_configuration.wordpress.id
  min_size             = 1
  max_size             = 3
  vpc_zone_identifier  = aws_subnet.public[*].id

  tag {
    key                 = "Name"
    value               = "WordPress"
    propagate_at_launch = true
  }
}

resource "aws_elb" "wordpress_elb" {
  name               = "WordPressELB"
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
  }

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  security_groups = [aws_security_group.web_sg.id]

  tags = {
    Name       = "WordPressELB"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-bucket"
  acl    = "public-read"

  tags = {
    Name       = "WordPressAssetsBucket"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_domain_name
    origin_id   = "wordpress-s3-origin"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for WordPress"
  
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-s3-origin"

    forwarded_values {
      query_string = false
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name       = "WordPressDistribution"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
  
  tags = {
    Name       = "WordPressHostedZone"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "www"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "rds_endpoint" {
  value = aws_rds_instance.wordpress_db.endpoint
}

output "elb_dns" {
  value = aws_elb.wordpress_elb.dns_name
}

output "s3_bucket_domain_name" {
  value = aws_s3_bucket.wordpress_assets.bucket_domain_name
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_distribution.domain_name
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}
