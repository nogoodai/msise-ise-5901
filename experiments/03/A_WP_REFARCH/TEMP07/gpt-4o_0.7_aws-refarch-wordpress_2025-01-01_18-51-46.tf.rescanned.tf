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
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks."
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "admin_ssh_cidr" {
  description = "CIDR block for SSH access to bastion host."
  type        = string
  default     = "192.168.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for WordPress."
  type        = string
  default     = "t2.micro"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t2.small"
}

variable "ami_id" {
  description = "AMI ID for the EC2 instances."
  type        = string
  default     = "ami-0c55b159cbfafe1f0"
}

variable "ssl_certificate_id" {
  description = "SSL certificate ID for HTTPS."
  type        = string
}

variable "domain_name" {
  description = "Domain name for Route 53 and CloudFront."
  type        = string
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "wordpress-vpc"
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

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = false
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "public-subnet-${count.index + 1}"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "private-subnet-${count.index + 1}"
    Environment = "production"
    Project     = "wordpress"
  }
}

data "aws_availability_zones" "available" {}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name        = "public-route-table"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  vpc_id      = aws_vpc.wordpress_vpc.id
  description = "Allow HTTP, HTTPS, and SSH access to web servers."

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
    cidr_blocks = [var.admin_ssh_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "web-sg"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id      = aws_vpc.wordpress_vpc.id
  description = "Allow MySQL access from the web servers."

  ingress {
    description    = "Allow MySQL traffic"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "db-sg"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_instance" "bastion" {
  ami           = var.ami_id
  instance_type = "t2.micro"
  subnet_id     = element(aws_subnet.public.*.id, 0)

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  associate_public_ip_address = false
  monitoring                  = true

  tags = {
    Name        = "bastion-host"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion.id
  tags = {
    Name        = "bastion-eip"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_efs_file_system" "wordpress_efs" {
  encrypted = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  performance_mode = "generalPurpose"
  tags = {
    Name        = "wordpress-efs"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_efs_mount_target" "wordpress_efs_mount" {
  count          = length(aws_subnet.private)
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_elb" "wordpress_alb" {
  name               = "wordpress-alb"
  availability_zones = data.aws_availability_zones.available.names

  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    protocol          = "HTTP"
  }

  listener {
    instance_port      = 443
    instance_protocol  = "HTTPS"
    lb_port            = 443
    protocol           = "HTTPS"
    ssl_certificate_id = var.ssl_certificate_id
  }

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  access_logs {
    enabled = true
    s3_bucket_name = "my-elb-logs"
  }

  tags = {
    Name        = "wordpress-alb"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.public.*.id
  launch_configuration = aws_launch_configuration.wordpress_lc.id
  load_balancers       = [aws_elb.wordpress_alb.id]

  tag {
    key                 = "Name"
    value               = "wordpress-instance"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-launch-configuration"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install -y php7.4
              yum install -y httpd mysql
              systemctl start httpd
              systemctl enable httpd
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_rds_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  instance_class       = var.db_instance_class
  name                 = "wordpressdb"
  username             = "admin"
  password             = var.db_password
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  multi_az             = true
  skip_final_snapshot  = true
  tags = {
    Name        = "wordpress-rds"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${random_id.bucket_id.hex}"
  acl    = "private"

  versioning {
    enabled = true
  }

  logging {
    target_bucket = "my-log-bucket"
    target_prefix = "s3-logs/"
  }

  tags = {
    Name        = "wordpress-assets"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "random_id" "bucket_id" {
  byte_length = 4
}

resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "wordpressS3"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpressS3"

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

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn            = var.ssl_certificate_id
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2018"
    cloudfront_default_certificate = false
  }

  logging_config {
    bucket = "my-cloudfront-logs.s3.amazonaws.com"
    include_cookies = false
    prefix = "wordpress/"
  }

  tags = {
    Name        = "wordpress-cdn"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name

  tags = {
    Name        = "wordpress-zone"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route53_record" "wordpress_alias" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cdn.hosted_zone_id
    evaluate_target_health = true
  }
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.wordpress_vpc.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public.*.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private.*.id
}

output "web_sg_id" {
  description = "ID of the web security group"
  value       = aws_security_group.web_sg.id
}

output "db_sg_id" {
  description = "ID of the database security group"
  value       = aws_security_group.db_sg.id
}

output "alb_dns_name" {
  description = "DNS name of the application load balancer"
  value       = aws_elb.wordpress_alb.dns_name
}

output "cdn_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.wordpress_cdn.domain_name
}

output "rds_endpoint" {
  description = "Endpoint of the RDS instance"
  value       = aws_rds_instance.wordpress_rds.endpoint
}

output "bastion_eip" {
  description = "Elastic IP of the bastion host"
  value       = aws_eip.bastion_eip.public_ip
}
