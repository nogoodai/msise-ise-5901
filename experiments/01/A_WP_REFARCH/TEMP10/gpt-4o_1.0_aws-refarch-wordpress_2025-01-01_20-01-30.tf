terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources"
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

variable "admin_ips" {
  description = "List of IPs allowed to SSH to bastion host"
  default     = ["0.0.0.0/0"]
}

variable "availability_zones" {
  description = "Availability zones for deployment"
  default     = ["us-west-2a", "us-west-2b"]
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "wordpress-vpc"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = element(var.public_subnet_cidrs, count.index)
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name        = "wordpress-public-${count.index}"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(var.availability_zones, count.index)
  tags = {
    Name        = "wordpress-private-${count.index}"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "wordpress-igw"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name        = "wordpress-public"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web" {
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
    cidr_blocks = var.admin_ips
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "wordpress-web-sg"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_security_group" "db" {
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    description             = "Allow MySQL"
    from_port               = 3306
    to_port                 = 3306
    protocol                = "tcp"
    security_groups         = [aws_security_group.web.id]
  }

  tags = {
    Name        = "wordpress-db-sg"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_instance" "bastion" {
  ami           = "ami-12345678" # Specify correct AMI
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.web.id]
  subnet_id              = aws_subnet.public[0].id

  tags = {
    Name        = "wordpress-bastion"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion.id
}

resource "aws_efs_file_system" "wordpress_efs" {
  performance_mode = "generalPurpose"

  tags = {
    Name        = "wordpress-efs"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_efs_mount_target" "wordpress_efs_mt" {
  count          = length(var.private_subnet_cidrs)
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.web.id]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  launch_configuration = aws_launch_configuration.wordpress_lc.id
  vpc_zone_identifier  = aws_subnet.public[*].id
  min_size             = 1
  max_size             = 3
  desired_capacity     = 1
  tags = [
    {
      key                 = "Name"
      value               = "wordpress-asg"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_lc" {
  image_id          = "ami-12345678" # Specify correct AMI
  instance_type     = "t2.micro"
  security_groups   = [aws_security_group.web.id]

  user_data = <<-EOF
    #!/bin/bash
    echo "Installing wordpress..."
  EOF
  
  lifecycle {
    create_before_destroy = true
  }

  key_name = "my-key"
}

resource "aws_elb" "wordpress_elb" {
  listeners = [
    {
      instance_port     = 80
      instance_protocol = "HTTP"
      lb_port           = 80
      lb_protocol       = "HTTP"
    }
  ]

  availability_zones = var.availability_zones
  security_groups    = [aws_security_group.web.id]
  
  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "wordpress-elb"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  instance_class       = "db.t2.small"
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password"  # Ensure secrets are handled securely
  parameter_group_name = "default.mysql5.7"
  multi_az             = true
  vpc_security_group_ids = [aws_security_group.db.id]
  subnet_group_name      = aws_db_subnet_group.wordpress.id

  tags = {
    Name        = "wordpress-db-instance"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_db_subnet_group" "wordpress" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "wordpress-db-subnet-group"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-static-assets"

  tags = {
    Name        = "wordpress-static-assets"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_s3_bucket_acl" "wordpress_acl" {
  bucket = aws_s3_bucket.wordpress_bucket.id
  acl    = "private"
}

resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_s3_bucket.wordpress_bucket.bucket_regional_domain_name
    origin_id   = "wordpressS3Origin"
  }

  enabled = true
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpressS3Origin"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  tags = {
    Name        = "wordpress-cloudfront"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress_elb_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "www.example.com"
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id                = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.wordpress_vpc.id
}

output "elb_dns" {
  description = "ELB DNS"
  value       = aws_elb.wordpress_elb.dns_name
}

output "db_endpoint" {
  description = "Database Endpoint"
  value       = aws_db_instance.wordpress_db.endpoint
}

output "cloudfront_domain_name" {
  description = "CloudFront Domain Name"
  value       = aws_cloudfront_distribution.wordpress_cf.domain_name
}

output "route53_zone_id" {
  description = "Route53 Hosted Zone ID"
  value       = aws_route53_zone.wordpress_zone.zone_id
}
