# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
  required_version = ">= 1.2.0"
}

# Set up the AWS provider
provider "aws" {
  region = "us-west-2"
}

# VPC and networking resources
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "Availability zones for the VPC"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

# Create public subnets
resource "aws_subnet" "public_subnets" {
  count             = length(var.availability_zones)
  cidr_block        = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicSubnet-${count.index}"
  }
}

# Create private subnets
resource "aws_subnet" "private_subnets" {
  count             = length(var.availability_zones)
  cidr_block        = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, length(var.availability_zones) + count.index)
  availability_zone = var.availability_zones[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateSubnet-${count.index}"
  }
}

# Create internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Create public route table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicRouteTable"
  }
}

# Create private route table
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

# Create route for public route table
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public_rta" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# Security groups
variable "web_server_sg_name" {
  type        = string
  default     = "WordPressWebServerSG"
  description = "Name of the web server security group"
}

resource "aws_security_group" "web_server_sg" {
  name        = var.web_server_sg_name
  description = "Allow inbound HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "Allow inbound HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow inbound HTTPS traffic"
    from_port   = 443
    to_port     = 443
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
    Name = var.web_server_sg_name
  }
}

variable "rds_sg_name" {
  type        = string
  default     = "WordPressRDSSG"
  description = "Name of the RDS security group"
}

resource "aws_security_group" "rds_sg" {
  name        = var.rds_sg_name
  description = "Allow inbound MySQL traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "Allow inbound MySQL traffic"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = var.rds_sg_name
  }
}

# EC2 instances for WordPress
variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for the EC2 instances"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
  description = "AMI ID for the EC2 instances"
}

resource "aws_instance" "wordpress_instances" {
  count         = 2
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.web_server_sg.id
  ]
  subnet_id = aws_subnet.public_subnets[count.index].id
  tags = {
    Name = "WordPressInstance-${count.index}"
  }
}

# RDS instance for the WordPress database
variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Instance class for the RDS instance"
}

variable "rds_database_name" {
  type        = string
  default     = "wordpressdb"
  description = "Name of the RDS database"
}

resource "aws_db_instance" "wordpress_rds" {
  instance_class = var.rds_instance_class
  engine         = "mysql"
  engine_version = "8.0.23"
  db_name        = var.rds_database_name
  username       = "admin"
  password       = "password123"
  vpc_security_group_ids = [
    aws_security_group.rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.rds_sng.name
  tags = {
    Name = "WordPressRDS"
  }
}

resource "aws_db_subnet_group" "rds_sng" {
  name       = "wordpress_rds_sng"
  subnet_ids = aws_subnet.private_subnets[*].id
  tags = {
    Name = "WordPressRDSSNG"
  }
}

# Elastic Load Balancer
variable "elb_name" {
  type        = string
  default     = "WordPressELB"
  description = "Name of the Elastic Load Balancer"
}

resource "aws_elb" "wordpress_elb" {
  name            = var.elb_name
  subnets         = aws_subnet.public_subnets[*].id
  security_groups = [aws_security_group.web_server_sg.id]

  listener {
    instance_port      = 80
    instance_protocol = "http"
    lb_port            = 80
    lb_protocol        = "http"
  }

  tags = {
    Name = var.elb_name
  }
}

# Auto Scaling Group for EC2 instances
variable "asg_name" {
  type        = string
  default     = "WordPressASG"
  description = "Name of the Auto Scaling Group"
}

resource "aws_autoscaling_group" "wordpress_asg" {
  name                 = var.asg_name
  launch_template {
    id      = aws_launch_template.wordpress_lt.id
    version = "$Latest"
  }
  min_size         = 2
  max_size         = 5
  vpc_zone_identifier = aws_subnet.public_subnets[*].id
  tags = [
    {
      key                 = "Name"
      value               = "WordPressASGInstance"
      propagate_at_launch = true
    },
  ]
}

resource "aws_launch_template" "wordpress_lt" {
  name-prefix = "wordpress-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_group_names = [
    var.web_server_sg_name
  ]
  key_name               = "wordpress-key"
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
}

# CloudFront distribution for content delivery
variable "cloudfront_distribution_name" {
  type        = string
  default     = "WordPressCloudFront"
  description = "Name of the CloudFront distribution"
}

resource "aws_cloudfront_distribution" "wordpress_cloudfront" {
  origin {
    domain_name = aws_s3_bucket.wordpress_bucket.bucket_regional_domain_name
    origin_id   = "S3Origin"
  }

  enabled = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"

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

  tags = {
    Name = var.cloudfront_distribution_name
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# S3 bucket for static assets
variable "s3_bucket_name" {
  type        = string
  default     = "wordpress-bucket"
  description = "Name of the S3 bucket"
}

resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = var.s3_bucket_name
  acl    = "private"

  tags = {
    Name = var.s3_bucket_name
  }
}

# Route 53 DNS configuration
variable "route53_zone_name" {
  type        = string
  default     = "example.com"
  description = "Name of the Route 53 zone"
}

resource "aws_route53_zone" "wordpress_zone" {
  name = var.route53_zone_name
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.route53_zone_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cloudfront.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cloudfront.zone_id
    evaluate_target_health = false
  }
}
