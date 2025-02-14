terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
  required_version = ">= 0.13"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy to"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "ssh_allowed_ips" {
  description = "IPs allowed to access via SSH"
  type        = list(string)
  default     = ["192.168.1.0/24"] # Changed for stricter access
}

variable "ami_id" {
  description = "AMI ID for the EC2 instances"
  type        = string
  default     = "ami-12345678"
}

variable "instance_type" {
  description = "Instance type for the EC2 instances"
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  description = "Name of the SSH key pair"
  type        = string
}

variable "db_username" {
  description = "Database username"
  type        = string
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "ssl_certificate_id" {
  description = "SSL Certificate ID for HTTPS"
  type        = string
}

variable "domain_name" {
  description = "Domain name for Route 53"
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

data "aws_availability_zones" "available" {}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = element(var.public_subnet_cidrs, count.index)
  map_public_ip_on_launch = false # Changed to false for security best practices
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  
  tags = {
    Name        = "wordpress-public-subnet-${count.index}"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  
  tags = {
    Name        = "wordpress-private-subnet-${count.index}"
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
    Name        = "wordpress-public-rt"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["192.168.1.0/24"] # Changed for stricter access
    description = "Allow HTTP from trusted IPs"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["192.168.1.0/24"] # Changed for stricter access
    description = "Allow HTTPS from trusted IPs"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_ips
    description = "Allow SSH from specific IPs"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  
  tags = {
    Name        = "wordpress-web-sg"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id

  ingress {
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
    security_groups  = [aws_security_group.web_sg.id]
    description      = "Allow MySQL from web security group"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  
  tags = {
    Name        = "wordpress-db-sg"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_instance" "bastion" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[0].id
  associate_public_ip_address = false # Changed to false to prevent public IP exposure
  key_name                    = var.key_name
  security_groups             = [aws_security_group.web_sg.name]
  monitoring                  = true # Enable detailed monitoring for observability
  
  tags = {
    Name        = "wordpress-bastion"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion.id
  vpc      = true

  tags = {
    Name        = "wordpress-bastion-eip"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_efs_file_system" "efs" {
  encrypted = true
  kms_key_id = aws_kms_key.efs_key.arn
  
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  
  tags = {
    Name        = "wordpress-efs"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_efs_mount_target" "mount_target" {
  count           = length(aws_subnet.private)
  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_kms_key" "efs_key" {
  description             = "KMS key for EFS encryption"
  deletion_window_in_days = 10
}

resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.public[*].id
  security_groups = [aws_security_group.web_sg.id]

  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  listener {
    instance_port      = 443
    instance_protocol  = "HTTPS"
    lb_port            = 443
    lb_protocol        = "HTTPS"
    ssl_certificate_id = var.ssl_certificate_id
  }

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  access_logs {
    bucket = aws_s3_bucket.elb_logs.bucket
    enabled = true
  }
  
  tags = {
    Name        = "wordpress-elb"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_s3_bucket" "elb_logs" {
  bucket = "wordpress-elb-logs"
  acl    = "private"
  
  tags = {
    Name        = "wordpress-elb-logs"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  vpc_zone_identifier  = aws_subnet.public[*].id
  launch_configuration = aws_launch_configuration.wordpress_lc.id
  min_size             = 1
  max_size             = 3
  desired_capacity     = 2
  health_check_type    = "ELB"
  load_balancers       = [aws_elb.wordpress_elb.name] # Associated ELB with ASG

  tags = [{
    key                 = "Name"
    value               = "wordpress-asg-instance"
    propagate_at_launch = true
  }]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name             = "wordpress-lc"
  image_id         = var.ami_id
  instance_type    = var.instance_type
  security_groups  = [aws_security_group.web_sg.id]
  key_name         = var.key_name
  user_data        = file("wordpress_install.sh")
}

resource "aws_rds_instance" "wordpress_db" {
  allocated_storage      = 20
  engine                 = "mysql"
  instance_class         = "db.t2.small"
  name                   = "wordpressdb"
  username               = var.db_username
  password               = var.db_password
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.wordpress_db_subnet.id
  multi_az               = true
  
  tags = {
    Name        = "wordpress-db"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_db_subnet_group" "wordpress_db_subnet" {
  name       = "wordpress-db-subnet"
  subnet_ids = aws_subnet.private[*].id
  
  tags = {
    Name        = "wordpress-db-subnet"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-static-assets"
  acl    = "private"

  versioning {
    enabled = true
  }

  logging {
    target_bucket = aws_s3_bucket.elb_logs.bucket
    target_prefix = "wordpress-assets/"
  }
  
  tags = {
    Name        = "wordpress-assets"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "wordpressS3Origin"
  }

  enabled              = true
  default_cache_behavior {
    target_origin_id       = "wordpressS3Origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    forwarded_values {
      query_string = false
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn            = var.ssl_certificate_id
    minimum_protocol_version       = "TLSv1.2_2019"
    ssl_support_method             = "sni-only"
  }
  
  logging_config {
    bucket = aws_s3_bucket.elb_logs.bucket
    include_cookies = false
    prefix = "cloudfront/"
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

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id                = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_cloudwatch_dashboard" "wordpress_dashboard" {
  dashboard_name = "wordpress-dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        x = 0
        y = 0
        width = 6
        height = 6
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.bastion.id]
          ]
          period = 300
          stat = "Average"
          region = var.region
          title = "EC2 CPU Utilization"
        }
      }
    ]
  })
}

output "bastion_ip" {
  value       = aws_eip.bastion_eip.public_ip
  description = "Public IP of the bastion host"
}

output "rds_endpoint" {
  value       = aws_rds_instance.wordpress_db.endpoint
  description = "RDS endpoint for the WordPress database"
}

output "elb_dns" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "DNS name of the WordPress ELB"
}

output "cloudfront_domain" {
  value       = aws_cloudfront_distribution.wordpress_cdn.domain_name
  description = "CloudFront domain for the WordPress CDN"
}
