terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.1.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy the infrastructure in."
  default     = "us-east-1"
}

variable "allowed_ssh_ips" {
  description = "The list of IPs allowed to SSH into EC2 instances."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "application_name" {
  description = "Application name for resource tagging."
  default     = "wordpress-app"
}

variable "environment" {
  description = "The environment for resource tagging (e.g., development, production)."
  default     = "production"
}

locals {
  vpc_cidr                 = "10.0.0.0/16"
  public_subnet_cidrs      = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs     = ["10.0.3.0/24", "10.0.4.0/24"]
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = local.vpc_cidr
  tags = {
    Name        = "${var.application_name}-vpc"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_subnet" "public" {
  count = length(local.public_subnet_cidrs)
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = local.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "${var.application_name}-public-subnet-${count.index+1}"
    Environment = var.environment
    Project     = var.application_name
  }
}

data "aws_availability_zones" "available" {}

resource "aws_subnet" "private" {
  count = length(local.private_subnet_cidrs)
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = local.private_subnet_cidrs[count.index]
  tags = {
    Name        = "${var.application_name}-private-subnet-${count.index+1}"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "${var.application_name}-igw"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name        = "${var.application_name}-public-rt"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)
  subnet_id = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_server_sg" {
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
    Name        = "${var.application_name}-web-sg"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_instance" "wordpress_instance" {
  count = 2
  ami             = "ami-12345678" # Placeholder for the actual AMI ID of Amazon Linux 2 or Ubuntu
  instance_type   = "t2.micro"
  subnet_id       = element(aws_subnet.public.*.id, count.index)
  security_groups = [aws_security_group.web_server_sg.name]
  key_name        = "your-key-name" # Specify the actual keypair name
  
  user_data = <<-EOF
              #!/bin/bash
              sudo yum install -y httpd php php-mysqlnd
              sudo systemctl start httpd
              sudo systemctl enable httpd
              EOF

  tags = {
    Name        = "${var.application_name}-web-${count.index+1}"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.public.*.id
  launch_configuration = aws_launch_configuration.wordpress_launch_config.id

  tags = [{
    key                 = "Name"
    value               = "${var.application_name}-asg"
    propagate_at_launch = true
  },
  {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  },
  {
    key                 = "Project"
    value               = var.application_name
    propagate_at_launch = true
  }]
}

resource "aws_launch_configuration" "wordpress_launch_config" {
  image_id        = "ami-12345678" # Placeholder for the actual AMI ID
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.web_server_sg.name]
  key_name        = "your-key-name"
  associate_public_ip_address = true
  user_data = <<-EOF
               #!/bin/bash
               sudo yum install -y httpd php php-mysqlnd
               sudo systemctl start httpd
               sudo systemctl enable httpd
               EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_elb" "wordpress_elb" {
  name               = "${var.application_name}-elb"
  subnets            = aws_subnet.public.*.id
  security_groups    = [aws_security_group.web_server_sg.id]

  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  listener {
    instance_port     = 443
    instance_protocol = "HTTP"
    lb_port           = 443
    lb_protocol       = "HTTPS"
    ssl_certificate_id = "arn:aws:acm:region:account-id:certificate/certificate-id"
  }

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "${var.application_name}-elb"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.wordpress_asg.name
  elb                    = aws_elb.wordpress_elb.name
}

resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  instance_class       = "db.t2.small"
  engine               = "mysql"
  engine_version       = "5.7"
  username             = "admin"
  password             = "password123" // Store securely with Terraform Vault or SSM Parameter Store
  db_name              = "wordpressdb"
  multi_az             = true
  publicly_accessible  = false
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnets.name

  tags = {
    Name        = "${var.application_name}-db"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_db_subnet_group" "wordpress_db_subnets" {
  name       = "${var.application_name}-db-subnet-group"
  subnet_ids = aws_subnet.private.*.id

  tags = {
    Name        = "${var.application_name}-db-subnet-group"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "${var.application_name}-assets"

  versioning {
    enabled = true
  }

  tags = {
    Name        = "${var.application_name}-assets"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.wordpress_assets.id}"
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.wordpress_assets.id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name        = "${var.application_name}-cdn"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_route53_zone" "wordpress_domain" {
  name = "example.com"

  tags = {
    Name        = "${var.application_name}-domain"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_domain.zone_id
  name    = "www.${aws_route53_zone.wordpress_domain.name}"
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id                = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = true
  }

  tags = {
    Name        = "${var.application_name}-dns-record"
    Environment = var.environment
    Project     = var.application_name
  }
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.wordpress_vpc.id
}

output "public_load_balancer_dns" {
  description = "The DNS name of the load balancer"
  value       = aws_elb.wordpress_elb.dns_name
}

output "s3_bucket_name" {
  description = "The name of the S3 bucket"
  value       = aws_s3_bucket.wordpress_assets.bucket
}

output "cloudfront_domain_name" {
  description = "The CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.wordpress_cdn.domain_name
}

output "rds_endpoint" {
  description = "The endpoint of the RDS database"
  value       = aws_db_instance.wordpress_db.endpoint
}

output "route53_zone_name" {
  description = "The name of the Route 53 hosted zone"
  value       = aws_route53_zone.wordpress_domain.name
}
