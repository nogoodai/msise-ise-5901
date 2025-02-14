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
  description = "The AWS region to deploy resources in."
  default     = "us-east-1"
  type        = string
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC."
  default     = "10.0.0.0/16"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "The CIDR blocks for the public subnets."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "The CIDR blocks for the private subnets."
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
  type        = list(string)
}

variable "allowed_ssh_cidrs" {
  description = "The CIDR blocks allowed to SSH into instances."
  default     = ["0.0.0.0/0"]
  type        = list(string)
}

variable "wordpress_instance_type" {
  description = "The instance type for WordPress EC2 instances."
  default     = "t2.micro"
  type        = string
}

variable "db_instance_class" {
  description = "The instance class for the RDS database."
  default     = "db.t2.small"
  type        = string
}

variable "db_username" {
  description = "The username for the RDS database."
  default     = "admin"
  type        = string
}

variable "db_password" {
  description = "The password for the RDS database."
  default     = "password"
  sensitive   = true
  type        = string
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr

  tags = {
    Name        = "WordPressVPC"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name        = "WordPressPublicSubnet-${count.index + 1}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private" {
  count    = length(var.private_subnet_cidrs)
  vpc_id   = aws_vpc.wordpress_vpc.id
  cidr_block = var.private_subnet_cidrs[count.index]

  tags = {
    Name        = "WordPressPrivateSubnet-${count.index + 1}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "WordPressIGW"
    Environment = "Production"
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
    Name        = "WordPressPublicRouteTable"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_server" {
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Security group for WordPress web servers."

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP traffic"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS traffic"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
    description = "Allow SSH traffic"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "WordPressWebServerSG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "database" {
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Security group for RDS database."

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server.id]
    description     = "Allow MySQL traffic from web servers"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "WordPressDatabaseSG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public[0].id
  associate_public_ip_address = false
  monitoring             = true

  key_name               = aws_key_pair.bastion_key.key_name

  vpc_security_group_ids = [aws_security_group.web_server.id]

  tags = {
    Name        = "BastionHost"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_key_pair" "bastion_key" {
  key_name   = "bastion-key"
  public_key = file("~/.ssh/id_rsa.pub")

  tags = {
    Name        = "BastionKey"
    Environment = "Production"
    Project     = "WordPress"
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  owners = ["amazon"]
}

resource "aws_db_instance" "wordpress" {
  engine                       = "mysql"
  instance_class               = var.db_instance_class
  allocated_storage            = 20
  name                         = "wordpressdb"
  username                     = var.db_username
  password                     = var.db_password
  parameter_group_name         = "default.mysql5.7"
  multi_az                     = true
  vpc_security_group_ids       = [aws_security_group.database.id]
  db_subnet_group_name         = aws_db_subnet_group.wordpress.name
  storage_encrypted            = true
  backup_retention_period      = 7
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]

  tags = {
    Name        = "WordPressDBInstance"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_db_subnet_group" "wordpress" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_elb" "wordpress_lb" {
  name               = "wordpress-lb"
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

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  security_groups = [aws_security_group.web_server.id]

  access_logs {
    enabled = true
    bucket  = aws_s3_bucket.elb_logs.bucket
  }

  tags = {
    Name        = "WordPressELB"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket" "elb_logs" {
  bucket_prefix = "elb-logs-"

  acl = "private"

  versioning {
    enabled = true
  }

  logging {
    target_bucket = aws_s3_bucket.wordpress_assets.id
    target_prefix = "logs/"
  }

  tags = {
    Name        = "ELBLogsBucket"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.public[*].id
  launch_configuration = aws_launch_configuration.wordpress_lc.id

  load_balancers = [aws_elb.wordpress_lb.name]

  tag {
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-launch-configuration"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.wordpress_instance_type
  security_groups = [aws_security_group.web_server.id]

  user_data = <<-EOF
                #!/bin/bash
                yum install -y httpd php php-mysqlnd
                systemctl enable httpd
                systemctl start httpd
                echo "<?php phpinfo(); ?>" > /var/www/html/index.php
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${random_id.bucket_suffix.hex}"

  versioning {
    enabled = true
  }

  logging {
    target_bucket = aws_s3_bucket.elb_logs.id
    target_prefix = "s3/"
  }

  tags = {
    Name        = "WordPressAssetsBucket"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "S3-wordpress-assets"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.php"

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
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = false
    acm_certificate_arn            = var.ssl_certificate_arn
    minimum_protocol_version       = "TLSv1.2_2018"
    ssl_support_method             = "sni-only"
  }

  logging_config {
    bucket = aws_s3_bucket.cloudfront_logs.bucket_regional_domain_name
    include_cookies = false
    prefix = "cloudfront/"
  }

  tags = {
    Name        = "WordPressCloudFront"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket" "cloudfront_logs" {
  bucket = "cloudfront-logs-${random_id.bucket_suffix.hex}"

  acl = "private"

  tags = {
    Name        = "CloudFrontLogsBucket"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route53_zone" "wordpress" {
  name = var.domain_name

  tags = {
    Name        = "WordPressRoute53Zone"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.wordpress.id
  name    = "www"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress.hosted_zone_id
    evaluate_target_health = false
  }
}

output "vpc_id" {
  value       = aws_vpc.wordpress_vpc.id
  description = "The ID of the VPC."
}

output "public_subnets" {
  value       = aws_subnet.public[*].id
  description = "The IDs of the public subnets."
}

output "private_subnets" {
  value       = aws_subnet.private[*].id
  description = "The IDs of the private subnets."
}

output "wordpress_db_endpoint" {
  value       = aws_db_instance.wordpress.endpoint
  description = "The endpoint of the WordPress RDS instance."
}

output "elb_dns_name" {
  value       = aws_elb.wordpress_lb.dns_name
  description = "The DNS name of the ELB."
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.wordpress.domain_name
  description = "The domain name of the CloudFront distribution."
}
