terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "wordpress-vpc"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "wordpress-igw"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "public_subnet" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = element(var.public_subnet_cidrs, count.index)
  map_public_ip_on_launch = true
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "wordpress-public-subnet-${count.index}"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private_subnet" {
  count     = length(var.private_subnet_cidrs)
  vpc_id    = aws_vpc.wordpress_vpc.id
  cidr_block = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "wordpress-private-subnet-${count.index}"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    description = "Allow HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Allow HTTPS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Allow SSH traffic"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["<YOUR_ADMIN_IP_RANGES>"]
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
    Project     = "WordPress"
  }
}

resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    description = "Allow MySQL traffic from Web SG"
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
    Name        = "wordpress-rds-sg"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_instance" "bastion_host" {
  ami           = "<AMI_ID>"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnet[0].id
  associate_public_ip_address = true
  key_name      = aws_key_pair.bastion_key.key_name

  security_groups = [aws_security_group.web_sg.name]

  tags = {
    Name        = "wordpress-bastion-host"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_key_pair" "bastion_key" {
  key_name   = "wordpress-bastion-key"
  public_key = file("<YOUR_PUBLIC_KEY_PATH>")
}

resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion_host.id
}

resource "aws_efs_file_system" "wordpress_efs" {
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  tags = {
    Name        = "wordpress-efs"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_efs_mount_target" "efs_mount_target" {
  count       = length(var.private_subnet_cidrs)
  file_system_id  = aws_efs_file_system.wordpress_efs.id
  subnet_id   = aws_subnet.private_subnet[count.index].id

  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_elb" "wordpress_elb" {
  name          = "wordpress-elb"
  availability_zones = data.aws_availability_zones.available.names
  security_groups   = [aws_security_group.web_sg.id]

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
    ssl_certificate_id = "<YOUR_SSL_CERT_ARN>"
  }

  health_check {
    target             = "HTTP:80/"
    interval           = 30
    timeout            = 5
    healthy_threshold  = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "wordpress-elb"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  availability_zones   = data.aws_availability_zones.available.names
  max_size             = 3
  min_size             = 1
  desired_capacity     = 2
  vpc_zone_identifier  = aws_subnet.private_subnet[*].id
  launch_configuration = aws_launch_configuration.wordpress_lc.id
  health_check_type    = "ELB"

  target_group_arns = [aws_elb.wordpress_elb.arn]

  tags = [{
    key   = "Name"
    value = "wordpress-asg"
    propagate_at_launch = true
  }]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-launch-config"
  image_id      = "<AMI_ID>"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.web_sg.id]

  associate_public_ip_address = false

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd php php-mysqlnd
              service httpd start
              chkconfig httpd on
              echo "<?php phpinfo(); ?>" > /var/www/html/phpinfo.php
              EOF

  iam_instance_profile = aws_iam_instance_profile.wordpress_ec2_profile.name
}

resource "aws_iam_role" "wordpress_ec2_role" {
  name = "wordpress-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_instance_profile" "wordpress_ec2_profile" {
  name = "wordpress-ec2-profile"
  role = aws_iam_role.wordpress_ec2_role.name
}

resource "aws_iam_policy_attachment" "wordpress_ec2_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  roles      = [aws_iam_role.wordpress_ec2_role.name]
}

resource "aws_rds_instance" "wordpress_rds" {
  allocated_storage    = 20
  instance_class       = "db.t2.small"
  engine               = "mysql"
  name                 = "wordpressdb"
  username             = "admin"
  password             = "YourDbPassword"
  parameter_group_name = "default.mysql5.7"
  skip_final_snapshot  = true
  publicly_accessible  = false
  multi_az             = true
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  tags = {
    Name        = "wordpress-rds"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "wordpress-s3-origin"
  }

  enabled = true
  default_cache_behavior {
    target_origin_id = "wordpress-s3-origin"

    forwarded_values {
      query_string = false
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA"]
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name        = "wordpress-cloudfront"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-static-assets-unique"
  
  tags = {
    Name        = "wordpress-assets"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = "<DOMAIN_NAME>"

  tags = {
    Name        = "wordpress-hosted-zone"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "<DOMAIN_NAME>"
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id                = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = true
  }
}

data "aws_availability_zones" "available" {}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.wordpress_vpc.id
}

output "alb_dns_name" {
  description = "The DNS name of the ALB"
  value       = aws_elb.wordpress_elb.dns_name
}

output "cloudfront_domain_name" {
  description = "The domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.wordpress_distribution.domain_name
}

output "s3_bucket_name" {
  description = "The name of the S3 bucket for static assets"
  value       = aws_s3_bucket.wordpress_assets.bucket
}

output "rds_endpoint" {
  description = "The endpoint of the RDS instance"
  value       = aws_rds_instance.wordpress_rds.endpoint
}
