provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "The environment in which this infrastructure is being deployed"
}

variable "project_name" {
  type        = string
  default     = "wordpress-project"
  description = "The name of the project"
}

variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block of the VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
  description = "The availability zones in which the instances will be deployed"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "The type of instance to deploy"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
  description = "The ID of the AMI to use"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "The class of the RDS instance"
}

variable "rds_username" {
  type        = string
  default     = "wordpressuser"
  sensitive   = true
  description = "The username for the RDS instance"
}

variable "rds_password" {
  type        = string
  default     = "wordpresspassword"
  sensitive   = true
  description = "The password for the RDS instance"
}

variable "rds_database_name" {
  type        = string
  default     = "wordpressdb"
  description = "The name of the database"
}

variable "cloudfront_domain_name" {
  type        = string
  default     = "example.com"
  description = "The domain name of the CloudFront distribution"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "public_subnets" {
  count = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name        = "${var.project_name}-public-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "private_subnets" {
  count = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 8, length(var.availability_zones) + count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "${var.project_name}-private-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table_association" "public_subnets_association" {
  count = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_security_group" "wordpress_sg" {
  name        = "${var.project_name}-wordpress-sg"
  description = "Allow HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow HTTP traffic from within the VPC"
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow HTTPS traffic from within the VPC"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outgoing traffic"
  }
  tags = {
    Name        = "${var.project_name}-wordpress-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow MySQL traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
    description     = "Allow MySQL traffic from the WordPress security group"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outgoing traffic"
  }
  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_instance" "wordpress_instances" {
  count = length(var.availability_zones)
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public_subnets[count.index].id
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  monitoring = true
  ebs_optimized = true
  tags = {
    Name        = "${var.project_name}-wordpress-instance-${count.index + 1}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_db_instance" "wordpress_rds" {
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = var.rds_instance_class
  allocated_storage    = 20
  storage_type         = "gp2"
  parameter_group_name = "default.mysql8.0"
  db_name              = var.rds_database_name
  username             = var.rds_username
  password             = var.rds_password
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  availability_zone = var.availability_zones[0]
  multi_az         = true
  storage_encrypted = true
  backup_retention_period = 12
  tags = {
    Name        = "${var.project_name}-wordpress-rds"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_elb" "wordpress_elb" {
  name            = "${var.project_name}-wordpress-elb"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_sg.id]
  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
  listener {
    instance_port      = 443
    instance_protocol  = "https"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  }
  access_logs {
    bucket        = "wordpress-elb-logs"
    bucket_prefix = "elb-logs"
    interval      = 60
  }
  tags = {
    Name        = "${var.project_name}-wordpress-elb"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "${var.project_name}-wordpress-asg"
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  min_size                  = 1
  max_size                  = 5
  desired_capacity         = 2
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id
  health_check_grace_period = 300
  health_check_type         = "EC2"
  load_balancers            = [aws_elb.wordpress_elb.name]
  force_delete              = true
  tags = [
    {
      key                 = "Name"
      value               = "${var.project_name}-wordpress-asg"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = var.environment
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = var.project_name
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name            = "${var.project_name}-wordpress-lc"
  image_id        = var.ami_id
  instance_type   = var.instance_type
  security_groups = [aws_security_group.wordpress_sg.id]
  user_data       = file("${path.module}/user_data.sh")
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }
  enabled         = true
  is_ipv6_enabled = true
  aliases         = [var.cloudfront_domain_name]
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-elb"
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
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  }
  logging_config {
    bucket = "wordpress-cdn-logs.s3.amazonaws.com"
    prefix = "cdn-logs/"
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  tags = {
    Name        = "${var.project_name}-wordpress-cdn"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_s3_bucket" "wordpress_static_assets" {
  bucket        = "${var.project_name}-wordpress-static-assets"
  acl           = "private"
  force_destroy = true
  versioning {
    enabled = true
  }
  logging {
    target_bucket = "wordpress-static-assets-logs"
    target_prefix = "s3-logs/"
  }
  tags = {
    Name        = "${var.project_name}-wordpress-static-assets"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name    = var.cloudfront_domain_name
  vpc {
    vpc_id = aws_vpc.wordpress_vpc.id
  }
  tags = {
    Name        = "${var.project_name}-wordpress-zone"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = var.cloudfront_domain_name
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
  tags = {
    Name        = "${var.project_name}-wordpress-record"
    Environment = var.environment
    Project     = var.project_name
  }
}

output "wordpress_vpc_id" {
  value       = aws_vpc.wordpress_vpc.id
  description = "The ID of the VPC"
}

output "wordpress_elb_dns_name" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "The DNS name of the ELB"
}

output "wordpress_rds_endpoint" {
  value       = aws_db_instance.wordpress_rds.endpoint
  description = "The endpoint of the RDS instance"
  sensitive   = true
}

output "wordpress_cdn_domain_name" {
  value       = aws_cloudfront_distribution.wordpress_cdn.domain_name
  description = "The domain name of the CloudFront distribution"
}

output "wordpress_static_assets_bucket_name" {
  value       = aws_s3_bucket.wordpress_static_assets.bucket
  description = "The name of the S3 bucket for static assets"
}

output "wordpress_zone_id" {
  value       = aws_route53_zone.wordpress_zone.zone_id
  description = "The ID of the Route 53 zone"
}
