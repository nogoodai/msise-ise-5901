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
  description = "The AWS region to deploy to."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet."
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet."
  type        = list(string)
  default     = ["10.0.2.0/24"]
}

variable "ami_id" {
  description = "AMI ID for the EC2 instances."
  type        = string
  default     = "ami-04505e74c0741db8d"
}

variable "instance_type" {
  description = "EC2 instance type for WordPress."
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  description = "Key pair for SSH access."
  type        = string
  default     = "my-key-pair"
}

resource "aws_vpc" "wordpress" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "public" {
  count                     = length(var.public_subnet_cidr)
  vpc_id                    = aws_vpc.wordpress.id
  cidr_block                = var.public_subnet_cidr[count.index]
  map_public_ip_on_launch   = false
  availability_zone         = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name        = "PublicSubnet-${count.index + 1}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidr)
  vpc_id            = aws_vpc.wordpress.id
  cidr_block        = var.private_subnet_cidr[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name        = "PrivateSubnet-${count.index + 1}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_internet_gateway" "wordpress" {
  vpc_id = aws_vpc.wordpress.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress.id
  }

  tags = {
    Name        = "PublicRouteTable"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidr)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  vpc_id      = aws_vpc.wordpress.id
  description = "Security group for web tier"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP from anywhere"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS from anywhere"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["your-ip-here/32"]
    description = "Allow SSH from designated IP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "WebServerSG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id      = aws_vpc.wordpress.id
  description = "Security group for database"

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
    description     = "Allow MySQL from web server"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "DatabaseSG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_instance" "bastion" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.public[0].id
  security_groups             = [aws_security_group.web_sg.id]
  associate_public_ip_address = false
  monitoring                  = true

  tags = {
    Name        = "BastionHost"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion.id
  vpc      = true
  tags = {
    Name        = "BastionEIP"
    Environment = "Production"
    Project     = "WordPress"
  }
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

  listener {
    instance_port       = 443
    instance_protocol   = "HTTPS"
    lb_port             = 443
    lb_protocol         = "HTTPS"
    ssl_certificate_id  = "arn:aws:acm:region:account:certificate/12345678-abcd-1234-abcd-12345678abcd"
  }

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  instances = [aws_instance.bastion.id]

  tags = {
    Name        = "WordPressELB"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_db_instance" "wordpress" {
  allocated_storage             = 20
  engine                        = "mysql"
  instance_class                = "db.t2.micro"
  name                          = "wordpressdb"
  username                      = "admin"
  password                      = var.db_password
  parameter_group_name          = "default.mysql8.0"
  multi_az                      = true
  vpc_security_group_ids        = [aws_security_group.db_sg.id]
  skip_final_snapshot           = true
  storage_encrypted             = true
  backup_retention_period       = 12
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]
  iam_database_authentication_enabled = true

  tags = {
    Name        = "WordPressDB"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  desired_capacity   = 2
  max_size           = 5
  min_size           = 1
  vpc_zone_identifier = aws_subnet.private[*].id

  launch_configuration = aws_launch_configuration.wordpress_lc.id

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

resource "aws_launch_configuration" "wordpress_lc" {
  name_prefix   = "wordpress-lc-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_sg.id]
  key_name      = var.key_name
  user_data     = file("path/to/your/user-data.sh")

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_s3_bucket.static_website.bucket_regional_domain_name
    origin_id   = "S3-origin"
  }

  enabled          = true
  is_ipv6_enabled  = true
  comment          = "CloudFront Distribution for WordPress"

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-origin"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy  = "redirect-to-https"
  }

  viewer_certificate {
    acm_certificate_arn     = "arn:aws:acm:region:account:certificate/12345678-abcd-1234-abcd-12345678abcd"
    ssl_support_method      = "sni-only"
    minimum_protocol_version = "TLSv1.2_2019"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  logging_config {
    bucket = "logs-bucket.s3.amazonaws.com"
    include_cookies = false
    prefix = "wordpress/"
  }

  tags = {
    Name        = "WordPressCloudFront"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket" "static_website" {
  bucket = "wordpress-static-assets"
  acl    = "private"

  versioning {
    enabled = true
  }

  logging {
    target_bucket = "log-bucket"
    target_prefix = "s3/"
  }

  tags = {
    Name        = "WordPressStaticAssets"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route53_zone" "wordpress" {
  name = "example.com"

  tags = {
    Name        = "WordPressRoute53Zone"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route53_record" "wordpress" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = "www.example.com"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress.hosted_zone_id
    evaluate_target_health = false
  }
}

data "aws_availability_zones" "available" {}

output "vpc_id" {
  value       = aws_vpc.wordpress.id
  description = "The ID of the VPC."
}

output "elb_dns_name" {
  value       = aws_elb.wordpress.dns_name
  description = "The DNS name of the ELB."
}

output "db_endpoint" {
  value       = aws_db_instance.wordpress.endpoint
  description = "The endpoint of the WordPress RDS database."
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.wordpress.domain_name
  description = "The domain name of the CloudFront distribution."
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.static_website.id
  description = "The name of the S3 bucket for static assets."
}

variable "db_password" {
  description = "The password for the RDS database."
  type        = string
  sensitive   = true
}
