provider "aws" {
  region = "us-west-2"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "The availability zones to use"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "The instance type to use for EC2 instances"
}

variable "db_instance_class" {
  type        = string
  default     = "db.t2.micro"
  description = "The instance class to use for RDS instances"
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "The environment to use for tagging"
}

variable "project" {
  type        = string
  default     = "wordpress"
  description = "The project to use for tagging"
}

# VPC
resource "aws_vpc" "wordpress-vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = var.environment
    Project     = var.project
  }
}

# Subnets
resource "aws_subnet" "public-subnet-1" {
  vpc_id            = aws_vpc.wordpress-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = var.availability_zones[0]
  tags = {
    Name        = "PublicSubnet1"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "public-subnet-2" {
  vpc_id            = aws_vpc.wordpress-vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = var.availability_zones[1]
  tags = {
    Name        = "PublicSubnet2"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "private-subnet-1" {
  vpc_id            = aws_vpc.wordpress-vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = var.availability_zones[0]
  tags = {
    Name        = "PrivateSubnet1"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "private-subnet-2" {
  vpc_id            = aws_vpc.wordpress-vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = var.availability_zones[1]
  tags = {
    Name        = "PrivateSubnet2"
    Environment = var.environment
    Project     = var.project
  }
}

# Internet Gateway
resource "aws_internet_gateway" "wordpress-igw" {
  vpc_id = aws_vpc.wordpress-vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = var.environment
    Project     = var.project
  }
}

# Public Route Table
resource "aws_route_table" "public-rt" {
  vpc_id = aws_vpc.wordpress-vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route" "public-internet-route" {
  route_table_id         = aws_route_table.public-rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress-igw.id
}

# Private Route Table
resource "aws_route_table" "private-rt" {
  vpc_id = aws_vpc.wordpress-vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = var.environment
    Project     = var.project
  }
}

# Associate Subnets with Route Tables
resource "aws_route_table_association" "public-subnet-1-assoc" {
  subnet_id      = aws_subnet.public-subnet-1.id
  route_table_id = aws_route_table.public-rt.id
}

resource "aws_route_table_association" "public-subnet-2-assoc" {
  subnet_id      = aws_subnet.public-subnet-2.id
  route_table_id = aws_route_table.public-rt.id
}

resource "aws_route_table_association" "private-subnet-1-assoc" {
  subnet_id      = aws_subnet.private-subnet-1.id
  route_table_id = aws_route_table.private-rt.id
}

resource "aws_route_table_association" "private-subnet-2-assoc" {
  subnet_id      = aws_subnet.private-subnet-2.id
  route_table_id = aws_route_table.private-rt.id
}

# Security Groups
resource "aws_security_group" "wordpress-sg" {
  vpc_id = aws_vpc.wordpress-vpc.id
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
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "WordPressSecurityGroup"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group" "rds-sg" {
  vpc_id = aws_vpc.wordpress-vpc.id
  ingress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
    security_groups = [aws_security_group.wordpress-sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "RDSSecurityGroup"
    Environment = var.environment
    Project     = var.project
  }
}

# EC2 Instances
resource "aws_instance" "wordpress-ec2-1" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public-subnet-1.id
  vpc_security_group_ids = [aws_security_group.wordpress-sg.id]
  key_name               = "wordpress-ec2-key"
  tags = {
    Name        = "WordPressEC2Instance1"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_instance" "wordpress-ec2-2" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public-subnet-2.id
  vpc_security_group_ids = [aws_security_group.wordpress-sg.id]
  key_name               = "wordpress-ec2-key"
  tags = {
    Name        = "WordPressEC2Instance2"
    Environment = var.environment
    Project     = var.project
  }
}

# RDS Instance
resource "aws_db_instance" "wordpress-rds" {
  engine           = "mysql"
  engine_version   = "5.7"
  instance_class   = var.db_instance_class
  username         = "wordpress-user"
  password         = "wordpress-password"
  db_name          = "wordpress-db"
  vpc_security_group_ids = [aws_security_group.rds-sg.id]
  multi_az         = true
  tags = {
    Name        = "WordPressRDSInstance"
    Environment = var.environment
    Project     = var.project
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress-elb" {
  name            = "WordPressELB"
  subnets         = [aws_subnet.public-subnet-1.id, aws_subnet.public-subnet-2.id]
  security_groups = [aws_security_group.wordpress-sg.id]
  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 80
    lb_protocol        = "http"
  }
  tags = {
    Name        = "WordPressELB"
    Environment = var.environment
    Project     = var.project
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress-asg" {
  name                = "WordPressASG"
  max_size            = 2
  min_size            = 1
  health_check_type   = "EC2"
  health_check_grace_period = 300
  launch_configuration = aws_launch_configuration.wordpress-lc.name
  vpc_zone_identifier  = aws_subnet.public-subnet-1.id
  tags = {
    Name        = "WordPressASG"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_launch_configuration" "wordpress-lc" {
  name          = "WordPressLC"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  security_groups = [aws_security_group.wordpress-sg.id]
  key_name               = "wordpress-ec2-key"
  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress-cfd" {
  origin {
    domain_name = aws_elb.wordpress-elb.dns_name
    origin_id   = "WordPressELB"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = ["example.com"]
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WordPressELB"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "allow-all"
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
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "snsv"
  }
  tags = {
    Name        = "WordPressCFD"
    Environment = var.environment
    Project     = var.project
  }
}

# S3 Bucket
resource "aws_s3_bucket" "wordpress-s3" {
  bucket = "wordpress-s3-bucket"
  acl    = "private"
  versioning {
    enabled = true
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
  tags = {
    Name        = "WordPressS3Bucket"
    Environment = var.environment
    Project     = var.project
  }
}

# Route 53 Hosted Zone
resource "aws_route53_zone" "wordpress-r53" {
  name = "example.com"
  tags = {
    Name        = "WordPressR53Zone"
    Environment = var.environment
    Project     = var.project
  }
}

# Route 53 Records
resource "aws_route53_record" "wordpress-r53-record" {
  zone_id = aws_route53_zone.wordpress-r53.zone_id
  name    = "example.com"
  type    = "A"
  alias {
    name                   = aws_elb.wordpress-elb.dns_name
    zone_id               = aws_elb.wordpress-elb.zone_id
    evaluate_target_health = true
  }
}

output "elb_dns_name" {
  value = aws_elb.wordpress-elb.dns_name
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress-rds.endpoint
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress-s3.bucket
}

output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress-cfd.domain_name
}
