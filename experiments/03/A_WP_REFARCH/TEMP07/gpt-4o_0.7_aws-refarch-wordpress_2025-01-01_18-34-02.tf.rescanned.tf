terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-west-2"
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

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
}

variable "allowed_ssh_cidr" {
  description = "CIDR block that is allowed to SSH into EC2 instances"
  type        = string
  default     = "192.168.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for WordPress"
  type        = string
  default     = "t2.micro"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
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

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false
  tags = {
    Name        = "WordPressPublicSubnet-${count.index}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "WordPressPrivateSubnet-${count.index}"
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

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Web security group for WordPress instances"

  ingress {
    description = "Allow HTTP from specific CIDR"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "Allow HTTPS from specific CIDR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "Allow SSH from specific CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WordPressWebSG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Database security group for RDS instance"

  ingress {
    description    = "Allow MySQL from Web SG"
    from_port      = 3306
    to_port        = 3306
    protocol       = "tcp"
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
    Name        = "WordPressDBSG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_instance" "bastion" {
  ami           = "ami-0abcdef1234567890" # Replace with actual AMI ID
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  associate_public_ip_address = false
  monitoring                  = true

  tags = {
    Name        = "WordPressBastion"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion.id
  tags = {
    Name        = "WordPressBastionEIP"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_efs_file_system" "wordpress_efs" {
  encrypted = true
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  throughput_mode = "bursting"

  tags = {
    Name        = "WordPressEFS"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_efs_mount_target" "wordpress_efs_mt" {
  count          = length(aws_subnet.private)
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_cloudwatch_metric_alarm" "efs_alarm" {
  alarm_name          = "EFS-Burst-Credit-Balance"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Sum"
  threshold           = 1000000000
  alarm_actions       = []

  tags = {
    Name        = "EFS-Burst-Credit-Balance"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_elb" "wordpress_elb" {
  name               = "wordpress-elb"
  availability_zones = var.availability_zones
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
    unhealthy_threshold = 2
    healthy_threshold   = 2
  }

  access_logs {
    enabled = true
    bucket  = aws_s3_bucket.logs.bucket
    prefix  = "elb"
  }

  security_groups = [aws_security_group.web_sg.id]

  tags = {
    Name        = "WordPressELB"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_launch_configuration" "wordpress_lc" {
  name                        = "wordpress-lc"
  image_id                    = "ami-0abcdef1234567890" # Replace with actual AMI ID
  instance_type               = var.instance_type
  security_groups             = [aws_security_group.web_sg.name]
  associate_public_ip_address = true
  user_data                   = file("user_data.sh")

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  min_size             = 2
  max_size             = 5
  desired_capacity     = 2
  vpc_zone_identifier  = aws_subnet.public[*].id
  load_balancers       = [aws_elb.wordpress_elb.name]

  tag {
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }

  tags = {
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_rds_instance" "wordpress_db" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.small"
  name                 = "wordpressdb"
  username             = "admin"
  password             = var.db_password
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  multi_az             = true
  skip_final_snapshot  = true

  tags = {
    Name        = "WordPressDB"
    Environment = "Production"
    Project     = "WordPress"
  }
}

variable "db_password" {
  description = "The password for the RDS database"
  type        = string
  sensitive   = true
}

resource "aws_db_subnet_group" "wordpress_db_subnet" {
  name       = "wordpress-db-subnet"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "WordPressDBSubnet"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-bucket"

  logging {
    target_bucket = aws_s3_bucket.logs.bucket
    target_prefix = "wordpress-assets/"
  }

  versioning {
    enabled = true
  }

  tags = {
    Name        = "WordPressAssets"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket" "logs" {
  bucket = "wordpress-logs-bucket"

  tags = {
    Name        = "WordPressLogs"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "wordpress-s3-origin"
  }

  enabled = true

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "wordpress-s3-origin"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  price_class = "PriceClass_100"

  viewer_certificate {
    cloudfront_default_certificate = false
    acm_certificate_arn            = var.acm_certificate_arn
    minimum_protocol_version       = "TLSv1.2_2019"
    ssl_support_method             = "sni-only"
  }

  logging_config {
    bucket = aws_s3_bucket.logs.bucket_domain_name
    include_cookies = false
    prefix = "cloudfront/"
  }

  tags = {
    Name        = "WordPressCDN"
    Environment = "Production"
    Project     = "WordPress"
  }
}

variable "acm_certificate_arn" {
  description = "The ARN of the ACM certificate to use for CloudFront"
  type        = string
}

resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"

  tags = {
    Name        = "WordPressHostedZone"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route53_record" "wordpress_alb" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "www.example.com"
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id                = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "wordpress_cdn_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "cdn.example.com"
  type    = "CNAME"
  ttl     = 300
  records = [aws_cloudfront_distribution.wordpress_cdn.domain_name]
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.wordpress_vpc.id
}

output "elb_dns_name" {
  description = "The DNS name of the ELB"
  value       = aws_elb.wordpress_elb.dns_name
}

output "rds_endpoint" {
  description = "The endpoint of the RDS instance"
  value       = aws_rds_instance.wordpress_db.endpoint
}

output "cloudfront_domain_name" {
  description = "The domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.wordpress_cdn.domain_name
}

output "s3_bucket_name" {
  description = "The name of the S3 bucket for static assets"
  value       = aws_s3_bucket.wordpress_assets.id
}
