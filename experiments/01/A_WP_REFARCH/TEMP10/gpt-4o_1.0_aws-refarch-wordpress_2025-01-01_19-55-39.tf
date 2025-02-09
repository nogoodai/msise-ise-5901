terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region to deploy resources"
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

variable "admin_ip" {
  description = "IP range for SSH access"
  default     = "0.0.0.0/32"
}

variable "instance_type" {
  description = "EC2 instance type for WordPress"
  default     = "t2.micro"
}

variable "db_instance_class" {
  description = "RDS instance class"
  default     = "db.t2.small"
}

variable "db_engine" {
  description = "RDS database engine"
  default     = "mysql"
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.public_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name        = "wordpress-public-subnet-${count.index}"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "wordpress-gateway"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name        = "wordpress-public-route-table"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name        = "wordpress-private-subnet-${count.index}"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_security_group" "web_sg" {
  name_prefix = "wordpress-web-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description      = "Allow HTTP traffic"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    description      = "Allow HTTPS traffic"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    description      = "Allow SSH access"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = [var.admin_ip]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "wordpress-web-sg"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_security_group" "db_sg" {
  name_prefix = "wordpress-db-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description      = "Allow MySQL access from web servers"
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
    security_groups  = [aws_security_group.web_sg.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "wordpress-db-sg"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  subnet_id              = element(aws_subnet.public.*.id, 0)
  associate_public_ip_address = true
  key_name               = var.key_pair
  security_groups        = [aws_security_group.web_sg.name]

  tags = {
    Name        = "wordpress-bastion"
    Environment = "production"
    Project     = "wordpress"
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

resource "aws_db_instance" "wordpress" {
  identifier              = "wordpress-db"
  engine                  = var.db_engine
  instance_class          = var.db_instance_class
  allocated_storage       = 20
  name                    = "wordpressdb"
  username                = var.db_username
  password                = var.db_password
  multi_az                = true
  vpc_security_group_ids  = [aws_security_group.db_sg.id]

  tags = {
    Name        = "wordpress-db-instance"
    Environment = "production"
    Project     = "wordpress"
  }
}

variable "db_username" {
  description = "Database username"
  default     = "admin"
}

variable "db_password" {
  description = "Database password"
}

resource "aws_elb" "wordpress" {
  name               = "wordpress-elb"
  availability_zones = data.aws_availability_zones.available.names
  security_groups    = [aws_security_group.web_sg.id]
  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  tags = {
    Name        = "wordpress-load-balancer"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_autoscaling_group" "wordpress" {
  launch_configuration = aws_launch_configuration.wordpress.name
  min_size             = 1
  max_size             = 3
  vpc_zone_identifier  = aws_subnet.private[*].id

  tags = [
    {
      key                 = "Name"
      value               = "wordpress-instance"
      propagate_at_launch = true
    },
  ]
}

resource "aws_launch_configuration" "wordpress" {
  name_prefix           = "wordpress-lc"
  image_id              = data.aws_ami.amazon_linux.id
  instance_type         = var.instance_type
  security_groups       = [aws_security_group.web_sg.name]
  user_data             = file("user_data.sh")

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_s3_bucket" "static_assets" {
  bucket = "wordpress-static-assets-${random_id.bucket_id.hex}"
  acl    = "private"

  tags = {
    Name        = "wordpress-static-assets"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "random_id" "bucket_id" {
  byte_length = 8
}

resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_elb.wordpress.dns_name
    origin_id   = "ELB-Origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
    }
  }

  enabled = true

  default_cache_behavior {
    target_origin_id       = "ELB-Origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
    }

    default_ttl = 3600
    max_ttl     = 86400
    min_ttl     = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name        = "wordpress-cloudfront"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route53_zone" "wordpress" {
  name = var.domain_name

  tags = {
    Name        = "wordpress-route53-zone"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress.hosted_zone_id
    evaluate_target_health = true
  }
}

variable "domain_name" {
  description = "Domain name for Route 53"
  default     = "example.com"
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "db_instance_endpoint" {
  value = aws_db_instance.wordpress.endpoint
}

output "elb_dns_name" {
  value = aws_elb.wordpress.dns_name
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress.domain_name
}
