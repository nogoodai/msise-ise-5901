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
  description = "The AWS region to deploy to"
  default     = "us-east-1"
}

variable "allowed_ssh_ips" {
  description = "List of IPs allowed to access the bastion host via SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Change this to specific IPs for production
}

data "aws_availability_zones" "available" {}

resource "aws_vpc" "wordpress" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "WordPressVPC"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress.id
  tags = {
    Name = "wordpress-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = length(data.aws_availability_zones.available.names)
  vpc_id                  = aws_vpc.wordpress.id
  cidr_block              = cidrsubnet(aws_vpc.wordpress.cidr_block, 3, count.index)
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "wordpress-public-${count.index}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress.id
  tags = {
    Name = "wordpress-public"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_subnet" "private" {
  count             = length(data.aws_availability_zones.available.names)
  vpc_id            = aws_vpc.wordpress.id
  cidr_block        = cidrsubnet(aws_vpc.wordpress.cidr_block, 3, count.index + length(data.aws_availability_zones.available.names))
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "wordpress-private-${count.index}"
  }
}

resource "aws_security_group" "web_sg" {
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

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress.id
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
    Name = "wordpress-db-sg"
  }
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.amazon_linux.latest.image_id
  instance_type = "t2.micro"
  vpc_security_group_ids = [
    aws_security_group.bastion_sg.id
  ]
  subnet_id = aws_subnet.public[0].id
  key_name  = var.key_name

  associate_public_ip_address = true

  tags = {
    Name = "wordpress-bastion"
  }
}

resource "aws_eip" "bastion_ip" {
  instance = aws_instance.bastion.id
  vpc      = true
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
  count         = length(aws_subnet.private)
  file_system_id = aws_efs_file_system.wordpress.id
  subnet_id      = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_elasticache_cluster" "wordpress" {
  cluster_id = "wordpress-cache"
  engine     = "redis"
  node_type  = "cache.t2.micro"
  num_cache_nodes = 1
  parameter_group_name = "default.redis3.2"
  subnet_group_name = aws_elasticache_subnet_group.wordpress.id
  tags = {
    Name = "wordpress-cache"
  }
}

resource "aws_elasticache_subnet_group" "wordpress" {
  name       = "wordpress-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_instance" "wordpress" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t2.small"
  name                 = "wordpressdb"
  username             = "admin"
  password             = var.db_password
  multi_az             = true
  storage_type         = "gp2"
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  tags = {
    Name = "wordpress-db"
  }
}

variable "db_password" {
  description = "The password for the WordPress DB"
  default     = "changeme123"  # Replace with a secure password in production
  sensitive   = true
}

resource "aws_elb" "wordpress" {
  name               = "wordpress-elb"
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
    ssl_certificate_id = var.ssl_certificate_id
  }

  instances = aws_autoscaling_group.wordpress_autoscaling_group.instances

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    unhealthy_threshold = 2
    healthy_threshold   = 2
  }

  tags = {
    Name = "wordpress-elb"
  }
}

variable "ssl_certificate_id" {
  description = "The ARN of the SSL certificate for HTTPS"
  default     = "arn:aws:acm:<region>:<account-id>:certificate/<id>"
}

resource "aws_autoscaling_group" "wordpress_autoscaling_group" {
  desired_capacity     = 2
  max_size             = 4
  min_size             = 2
  vpc_zone_identifier  = aws_subnet.public[*].id
  launch_configuration = aws_launch_configuration.wordpress.id

  tag {
    key                 = "Name"
    value               = "wordpress-autoscaling"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress" {
  name          = "wordpress-launch-config"
  image_id      = data.aws_ami.amazon_linux.latest.image_id
  instance_type = "t2.medium"
  key_name      = var.key_name

  security_groups = [
    aws_security_group.web_sg.id
  ]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              # Additional setup such as installing WordPress and connecting to the database
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-static-assets"

  tags = {
    Name = "wordpress-assets"
  }
}

resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "S3-wordpress-assets"
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-wordpress-assets"

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

  tags = {
    Name = "wordpress-cloudfront"
  }
}

resource "aws_route53_zone" "wordpress" {
  name = "example.com"
}

resource "aws_route53_record" "alb" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = "wordpress.example.com"
  type    = "A"
  alias {
    name                   = aws_elb.wordpress.dns_name
    zone_id                = aws_elb.wordpress.zone_id
    evaluate_target_health = true
  }
}

output "vpc_id" {
  value = aws_vpc.wordpress.id
}

output "bastion_ip" {
  value = aws_eip.bastion_ip.public_ip
}

output "efs_id" {
  value = aws_efs_file_system.wordpress.id
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress.endpoint
}

output "elb_dns_name" {
  value = aws_elb.wordpress.dns_name
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress.domain_name
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}
