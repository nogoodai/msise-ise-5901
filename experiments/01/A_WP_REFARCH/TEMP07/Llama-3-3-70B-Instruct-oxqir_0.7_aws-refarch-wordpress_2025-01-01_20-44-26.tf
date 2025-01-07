# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.16.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

# VPC Configuration
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}
variable "public_subnets" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "The CIDR blocks for the public subnets"
}
variable "private_subnets" {
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
  description = "The CIDR blocks for the private subnets"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnets)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnets[count.index]
  availability_zone = "${aws_vpc.wordpress_vpc.region}a"
  tags = {
    Name = "PublicSubnet${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnets)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = "${aws_vpc.wordpress_vpc.region}a"
  tags = {
    Name = "PrivateSubnet${count.index + 1}"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route" "public_internet_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table_association" "public_subnet_association" {
  count          = length(var.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Security Groups
variable "web_server_sg_name" {
  type        = string
  default     = "WordPressWebServerSG"
  description = "The name of the security group for the web server"
}
variable "db_sg_name" {
  type        = string
  default     = "WordPressDBSG"
  description = "The name of the security group for the database"
}

resource "aws_security_group" "web_server_sg" {
  name        = var.web_server_sg_name
  description = "Security group for the web server"
  vpc_id      = aws_vpc.wordpress_vpc.id
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

resource "aws_security_group" "db_sg" {
  name        = var.db_sg_name
  description = "Security group for the database"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    description = "Allow MySQL traffic from the web server"
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
    Name = var.db_sg_name
  }
}

# EC2 Instances for WordPress
variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "The instance type for the WordPress instances"
}
variable "ami_id" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
  description = "The ID of the AMI for the WordPress instances"
}

resource "aws_instance" "wordpress_instances" {
  count         = 2
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.web_server_sg.id
  ]
  subnet_id = aws_subnet.public_subnets[count.index].id
  key_name               = "wordpress_key"
  tags = {
    Name = "WordPressInstance${count.index + 1}"
  }
}

# RDS Instance for the WordPress Database
variable "db_instance_class" {
  type        = string
  default     = "db.t2.micro"
  description = "The instance class for the database instance"
}
variable "db_instance_identifier" {
  type        = string
  default     = "wordpress-db"
  description = "The identifier for the database instance"
}

resource "aws_db_instance" "wordpress_db" {
  identifier           = var.db_instance_identifier
  instance_class       = var.db_instance_class
  engine               = "mysql"
  engine_version       = "8.0.23"
  db_name              = "wordpressdb"
  username             = "wordpressuser"
  password             = "wordpresspassword"
  vpc_security_group_ids = [
    aws_security_group.db_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  tags = {
    Name = var.db_instance_identifier
  }
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress_db_subnet_group"
  subnet_ids = aws_subnet.private_subnets[*].id
  tags = {
    Name = "WordPressDBSubnetGroup"
  }
}

# Elastic Load Balancer
variable "elb_name" {
  type        = string
  default     = "wordpress-elb"
  description = "The name of the Elastic Load Balancer"
}

resource "aws_elb" "wordpress_elb" {
  name            = var.elb_name
  subnets         = aws_subnet.public_subnets[*].id
  security_groups = [
    aws_security_group.web_server_sg.id
  ]
  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 80
    lb_protocol        = "http"
  }
  listener {
    instance_port      = 443
    instance_protocol  = "https"
    lb_port            = 443
    lb_protocol        = "https"
  }
  tags = {
    Name = var.elb_name
  }
}

# Auto Scaling Group for EC2 Instances
variable "asg_name" {
  type        = string
  default     = "wordpress-asg"
  description = "The name of the Auto Scaling Group"
}
variable "asg_min_size" {
  type        = number
  default     = 2
  description = "The minimum size of the Auto Scaling Group"
}
variable "asg_max_size" {
  type        = number
  default     = 5
  description = "The maximum size of the Auto Scaling Group"
}

resource "aws_autoscaling_group" "wordpress_asg" {
  name                 = var.asg_name
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  min_size             = var.asg_min_size
  max_size             = var.asg_max_size
  vpc_zone_identifier = aws_subnet.public_subnets[*].id
  tags = [
    {
      key                 = "Name"
      value               = "WordPressASG"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.web_server_sg.id
  ]
  key_name               = "wordpress_key"
}

# CloudFront Distribution
variable "cloudfront_distribution_name" {
  type        = string
  default     = "wordpress-cloudfront"
  description = "The name of the CloudFront distribution"
}

resource "aws_cloudfront_distribution" "wordpress_cloudfront" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "S3Origin"
  }
  enabled = true
  default_root_object = "index.html"
  aliases = ["example.com", "www.example.com"]
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
  viewer_certificate {
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "sni-only"
  }
}

# S3 Bucket for Static Assets
variable "s3_bucket_name" {
  type        = string
  default     = "wordpress-static-assets"
  description = "The name of the S3 bucket for static assets"
}

resource "aws_s3_bucket" "wordpress_static_assets" {
  bucket = var.s3_bucket_name
  acl    = "private"
  tags = {
    Name = var.s3_bucket_name
  }
}

# Route 53 DNS Configuration
variable "route53_domain_name" {
  type        = string
  default     = "example.com"
  description = "The domain name for the Route 53 DNS configuration"
}

resource "aws_route53_zone" "wordpress_route53" {
  name = var.route53_domain_name
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53.id
  name    = var.route53_domain_name
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id                = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = true
  }
}

# Output the IDs and ARNs of the created resources
output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}
output "elb_id" {
  value = aws_elb.wordpress_elb.id
}
output "asg_id" {
  value = aws_autoscaling_group.wordpress_asg.id
}
output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.wordpress_cloudfront.id
}
output "s3_bucket_arn" {
  value = aws_s3_bucket.wordpress_static_assets.arn
}
output "route53_zone_id" {
  value = aws_route53_zone.wordpress_route53.id
}
