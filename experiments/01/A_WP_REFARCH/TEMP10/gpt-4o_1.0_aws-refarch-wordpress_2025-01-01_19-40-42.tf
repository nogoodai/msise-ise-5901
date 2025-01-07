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
  default = "us-east-1"
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

variable "admin_ip" {
  description = "The IP address for SSH access to the bastion host"
  default     = "0.0.0.0/0"  # Adjust to specific IP for security
}

variable "key_name" {
  description = "SSH key pair for bastion host access"
  default     = "my-key"
}

locals {
  tags = {
    Project     = "WordPress"
    Environment = "Production"
  }
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = merge(local.tags, { Name = "WordPressVPC" })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags   = merge(local.tags, { Name = "WordPressIGW" })
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = element(var.public_subnet_cidrs, count.index)
  map_public_ip_on_launch = true
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = merge(local.tags, { Name = "WordPressPublicSubnet-${count.index}" })
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = merge(local.tags, { Name = "WordPressPrivateSubnet-${count.index}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = merge(local.tags, { Name = "WordPressPublicRT" })
}

resource "aws_route_table_association" "public_subnet_association" {
  count          = length(aws_subnet.public)
  subnet_id      = element(aws_subnet.public.*.id, count.index)
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
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.tags, { Name = "WordPressWebSG" })
}

resource "aws_security_group" "bastion_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.tags, { Name = "WordPressBastionSG" })
}

resource "aws_key_pair" "bastion_key" {
  key_name   = var.key_name
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "aws_instance" "bastion_host" {
  ami             = "ami-0c55b159cbfafe1f0"  # Example Amazon Linux 2 AMI
  instance_type   = "t2.micro"
  key_name        = aws_key_pair.bastion_key.key_name
  subnet_id       = aws_subnet.public[0].id
  security_groups = [aws_security_group.bastion_sg.name]
  associate_public_ip_address = true
  tags = merge(local.tags, { Name = "WordPressBastion" })
}

resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion_host.id
  vpc      = true
}

resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.tags, { Name = "WordPressRDSSG" })
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private.*.id
  tags = merge(local.tags, { Name = "WordPressDBSubnetGroup" })
}

resource "aws_db_instance" "wordpress_db" {
  identifier              = "wordpress-db"
  allocated_storage       = 20
  engine                  = "mysql"
  instance_class          = "db.t2.small"
  username                = "admin"
  password                = "password"  # Change this to a secure password
  parameter_group_name    = "default.mysql8.0"
  multi_az                = true
  skip_final_snapshot     = true
  db_subnet_group_name    = aws_db_subnet_group.wordpress_db_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  tags = merge(local.tags, { Name = "WordPressDB" })
}

resource "aws_s3_bucket" "static_assets" {
  bucket = "wordpress-static-assets-${random_pet.bucket_name.id}"
  acl    = "public-read"
  tags   = merge(local.tags, { Name = "WordPressStaticAssets" })
}

resource "random_pet" "bucket_name" {
  length = 2
}

resource "aws_s3_bucket_policy" "static_assets_policy" {
  bucket = aws_s3_bucket.static_assets.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "PublicReadGetObject"
        Effect = "Allow"
        Principal = "*"
        Action = "s3:GetObject"
        Resource = "${aws_s3_bucket.static_assets.arn}/*"
      }
    ]
  })
}

resource "aws_elb" "wordpress_alb" {
  name               = "wordpress-alb"
  availability_zones = data.aws_availability_zones.available.names
  security_groups    = [aws_security_group.web_sg.id]
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
    ssl_certificate_id = "<your-ssl-certificate-id>"
  }
  tags = merge(local.tags, { Name = "WordPressALB" })
}

resource "aws_autoscaling_group" "wordpress_asg" {
  launch_configuration = aws_launch_configuration.wordpress_lc.id
  min_size             = 1
  max_size             = 3
  vpc_zone_identifier  = aws_subnet.private.*.id
  tags = [
    {
      key                 = "Name"
      value               = "WordPressEC2"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = "Production"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-launch-configuration"
  image_id      = "ami-0c55b159cbfafe1f0"  # Example Amazon Linux 2 AMI
  instance_type = "t2.micro"
  security_groups = [
    aws_security_group.web_sg.id
  ]
  user_data = <<-EOF
              #!/bin/bash
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              # Additional WordPress setup commands
              EOF
}

resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_s3_bucket.static_assets.bucket_regional_domain_name
    origin_id   = "S3-wordpress-static-assets"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    target_origin_id = "S3-wordpress-static-assets"

    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  tags = merge(local.tags, { Name = "WordPressCloudFront" })
}

data "aws_route53_zone" "wordpress_zone" {
  name         = "example.com"  # Replace with your domain
  private_zone = false
}

resource "aws_route53_record" "wordpress_alb_record" {
  zone_id = data.aws_route53_zone.wordpress_zone.zone_id
  name    = "www"
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_alb.dns_name
    zone_id                = aws_elb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "wordpress_cdn_record" {
  zone_id = data.aws_route53_zone.wordpress_zone.zone_id
  name    = "cdn"
  type    = "CNAME"
  ttl     = 300
  records = [aws_cloudfront_distribution.wordpress_cdn.domain_name]
}

data "aws_availability_zones" "available" {}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.wordpress_vpc.id
}

output "bastion_ip" {
  description = "The Elastic IP of the Bastion host"
  value       = aws_eip.bastion_eip.public_ip
}

output "db_instance_endpoint" {
  description = "The endpoint of the RDS instance"
  value       = aws_db_instance.wordpress_db.endpoint
}

output "elb_dns_name" {
  description = "The DNS name of the Elastic Load Balancer"
  value       = aws_elb.wordpress_alb.dns_name
}

output "cloudfront_distribution_domain_name" {
  description = "The domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.wordpress_cdn.domain_name
}
