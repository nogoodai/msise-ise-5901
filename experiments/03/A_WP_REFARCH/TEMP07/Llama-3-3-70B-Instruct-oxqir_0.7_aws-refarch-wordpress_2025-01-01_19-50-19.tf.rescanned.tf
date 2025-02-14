# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Define variables for the configuration
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}

variable "subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "The CIDR blocks for the subnets"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
  description = "The availability zones for the subnets"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "The instance type for the EC2 instances"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
  description = "The ID of the AMI for the EC2 instances"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "The instance class for the RDS instance"
}

variable "rds_engine" {
  type        = string
  default     = "mysql"
  description = "The engine for the RDS instance"
}

variable "rds_username" {
  type        = string
  default     = "admin"
  description = "The username for the RDS instance"
}

variable "rds_password" {
  type      = string
  sensitive = true
  description = "The password for the RDS instance"
}

variable "cloudfront_ssl_certificate_arn" {
  type        = string
  default     = ""
  description = "The ARN of the SSL certificate for CloudFront"
}

# Create a VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# Create subnets
resource "aws_subnet" "wordpress_subnets" {
  count             = length(var.subnet_cidrs)
  cidr_block        = var.subnet_cidrs[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "WordPressSubnet${count.index}"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# Create an internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# Create a public route table
resource "aws_route_table" "wordpress_public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressPublicRT"
    Environment = "prod"
    Project     = "wordpress"
  }
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
}

# Create a private route table
resource "aws_route_table" "wordpress_private_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressPrivateRT"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# Associate subnets with route tables
resource "aws_route_table_association" "wordpress_public_rt_assoc" {
  count          = length(var.subnet_cidrs)
  subnet_id      = aws_subnet.wordpress_subnets[count.index].id
  route_table_id = aws_route_table.wordpress_public_rt.id
}

resource "aws_route_table_association" "wordpress_private_rt_assoc" {
  count          = length(var.subnet_cidrs)
  subnet_id      = aws_subnet.wordpress_subnets[count.index].id
  route_table_id = aws_route_table.wordpress_private_rt.id
}

# Create security groups
resource "aws_security_group" "wordpress_web_sg" {
  name        = "wordpress-web-sg"
  description = "Allow HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "WordPressWebSG"
    Environment = "prod"
    Project     = "wordpress"
  }
}

resource "aws_security_group" "wordpress_db_sg" {
  name        = "wordpress-db-sg"
  description = "Allow MySQL traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_web_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "WordPressDBSG"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# Create RDS instance
resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = var.rds_engine
  engine_version       = "8.0.28"
  instance_class       = var.rds_instance_class
  name                 = "wordpressdb"
  username             = var.rds_username
  password             = var.rds_password
  parameter_group_name = "default.mysql8.0"
  vpc_security_group_ids = [
    aws_security_group.wordpress_db_sg.id
  ]
  storage_encrypted = true
  multi_az             = true
  backup_retention_period = 12
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]
  tags = {
    Name        = "WordPressDB"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# Create EC2 instances
resource "aws_instance" "wordpress_ec2" {
  count         = 2
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.wordpress_web_sg.id
  ]
  subnet_id = aws_subnet.wordpress_subnets[count.index].id
  associate_public_ip_address = false
  ebs_optimized = true
  monitoring = true
  tags = {
    Name        = "WordPressEC2${count.index}"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# Create an Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "wordpress-asg"
  max_size            = 5
  min_size            = 2
  vpc_zone_identifier = aws_subnet.wordpress_subnets[0].id
  launch_template {
    id      = aws_launch_template.wordpress_lt.id
    version = "$Latest"
  }
  load_balancers = [aws_elb.wordpress_elb.name]
  tags = {
    Name        = "WordPressASG"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# Create a Launch Template
resource "aws_launch_template" "wordpress_lt" {
  name          = "wordpress-lt"
  image_id      = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.wordpress_web_sg.id
  ]
  user_data = base64encode("echo 'WordPress installation script'")
  tags = {
    Name        = "WordPressLT"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# Create an Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.wordpress_subnets.*.id
  security_groups = [aws_security_group.wordpress_web_sg.id]
  access_logs {
    bucket        = "wordpress-elb-logs"
    bucket_prefix = "elb-logs"
    interval      = 60
  }
  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 80
    lb_protocol        = "http"
  }
  tags = {
    Name        = "WordPressELB"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# Create a CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb-origin"
  }
  enabled             = true
  default_root_object = "index.html"
  aliases             = ["example.com"]
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-elb-origin"
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
    acm_certificate_arn = var.cloudfront_ssl_certificate_arn
    ssl_support_method  = "sni-only"
    minimum_protocol_version = "TLSv1.2_2019"
  }
  logging_config {
    bucket = "wordpress-cfd-logs.s3.amazonaws.com"
    prefix = "cfd-logs"
  }
  tags = {
    Name        = "WordPressCFD"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# Create an S3 bucket
resource "aws_s3_bucket" "wordpress_s3" {
  bucket        = "wordpress-s3-bucket"
  force_destroy = true
  versioning {
    enabled = true
  }
  logging {
    target_bucket = "wordpress-s3-logs"
    target_prefix = "s3-logs/"
  }
  tags = {
    Name        = "WordPressS3"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# Create a Route 53 hosted zone
resource "aws_route53_zone" "wordpress_r53" {
  name = "example.com"
  tags = {
    Name        = "WordPressR53"
    Environment = "prod"
    Project     = "wordpress"
  }
}

# Create Route 53 records
resource "aws_route53_record" "wordpress_r53_record" {
  zone_id = aws_route53_zone.wordpress_r53.zone_id
  name    = "example.com"
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "wordpress_cfd_record" {
  zone_id = aws_route53_zone.wordpress_r53.zone_id
  name    = "example.com"
  type    = "CNAME"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cfd.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cfd.zone_id
    evaluate_target_health = false
  }
}

output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "subnet_ids" {
  value = aws_subnet.wordpress_subnets.*.id
}

output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "rds_instance_arn" {
  value = aws_db_instance.wordpress_db.arn
}

output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cfd.domain_name
}
