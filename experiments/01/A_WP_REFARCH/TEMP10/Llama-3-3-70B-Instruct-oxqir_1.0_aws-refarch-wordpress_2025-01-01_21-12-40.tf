# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.1.0"
    }
  }
}

# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
}

# Variables definition
variable "environment" {
  default = "dev"
}

variable "project_name" {
  default = "wordpress"
}

variable "vpc_cidr_block" {
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  default = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "instance_type" {
  default = "t2.micro"
}

variable "ami_id" {
  default = "ami-0c2ab3b8efb09f272"
}

variable "database_instance_class" {
  default = "db.t2.small"
}

variable "database_username" {
  default = "wordpress_user"
}

variable "database_password" {
  default = "password123"
}

variable "database_name" {
  default = "wordpress_db"
}

variable "cache_node_type" {
  default = "cache.t2.micro"
}

variable "cache_engine" {
  default = "memcached"
}

variable "s3_bucket_name" {
  default = "wordpress-static-assets"
}

variable "distribution_domain_name" {
  default = "d2mu5k2fz9okiw.cloudfront.net"
}

variable "route53_zone_name" {
  default = "example.com"
}

variable "ssh_key_name" {
  default = "wordpress-ssh-key"
}

# VPC configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name        = "WordPressVPC"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Subnets configuration
resource "aws_subnet" "public_subnet" {
  count = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PublicSubnet${count.index + 1}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "private_subnet" {
  count = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, length(var.availability_zones) + count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PrivateSubnet${count.index + 1}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Internet Gateway configuration
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Route Tables configuration
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name        = "PublicRouteTable"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Route Table Associations
resource "aws_route_table_association" "public_subnet_association" {
  count = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnet_association" {
  count = length(var.availability_zones)
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security Groups configuration
resource "aws_security_group" "ec2_security_group" {
  name        = "WordPressEC2SecurityGroup"
  description = "Security Group for WordPress EC2 instances"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
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
    Name        = "WordPressEC2SecurityGroup"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_security_group" "rds_security_group" {
  name        = "WordPressRDSSecurityGroup"
  description = "Security Group for WordPress RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.ec2_security_group.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "WordPressRDSSecurityGroup"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_security_group" "elb_security_group" {
  name        = "WordPressELBSecurityGroup"
  description = "Security Group for WordPress ELB"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
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
    Name        = "WordPressELBSecurityGroup"
    Environment = var.environment
    Project     = var.project_name
  }
}

# EC2 instances configuration
resource "aws_instance" "wordpress_ec2_instance" {
  count = 3
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id      = aws_subnet.public_subnet[count.index].id
  vpc_security_group_ids = [
    aws_security_group.ec2_security_group.id
  ]
  key_name               = var.ssh_key_name
  tags = {
    Name        = "WordPressEC2Instance${count.index + 1}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# RDS instance configuration
resource "aws_db_instance" "wordpress_rds_instance" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = var.database_instance_class
  name                 = var.database_name
  username             = var.database_username
  password             = var.database_password
  vpc_security_group_ids = [
    aws_security_group.rds_security_group.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  tags = {
    Name        = "WordPressRDSInstance"
    Environment = var.environment
    Project     = var.project_name
  }
}

# RDS subnet group configuration
resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "WordPressRDSSubnetGroup"
  subnet_ids = aws_subnet.private_subnet.*.id
  tags = {
    Name        = "WordPressRDSSubnetGroup"
    Environment = var.environment
    Project     = var.project_name
  }
}

# ELB configuration
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = aws_subnet.public_subnet.*.id
  security_groups = [aws_security_group.elb_security_group.id]
  listener {
    lb_port       = 80
    lb_protocol   = "http"
    instance_port = 80
    instance_protocol = "http"
  }
  tags = {
    Name        = "WordPressELB"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Auto Scaling Group configuration
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  launch_configuration      = aws_launch_configuration.wordpress_launch_config.name
  min_size                  = 3
  max_size                  = 6
  vpc_zone_identifier       = aws_subnet.public_subnet.*.id
  tags = [
    {
      key                 = "Name"
      value               = "WordPressASG"
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

# Launch Configuration configuration
resource "aws_launch_configuration" "wordpress_launch_config" {
  name          = "WordPressLaunchConfig"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.ec2_security_group.id
  ]
  key_name = var.ssh_key_name
  user_data = file("${path.module}/user_data.sh")
}

# CloudFront configuration
resource "aws_cloudfront_distribution" "wordpress_cloudfront_distribution" {
  enabled         = true
  is_ipv6_enabled = true
  default_root_object = "index.html"
  aliases = [
    var.distribution_domain_name
  ]
  default_cache_behavior {
    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]
    target_origin_id       = "WordPressOrigin"
    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressOrigin"
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
  tags = {
    Name        = "WordPressCloudFrontDistribution"
    Environment = var.environment
    Project     = var.project_name
  }
}

# S3 bucket configuration
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = var.s3_bucket_name
  acl    = "private"
  tags = {
    Name        = "WordPressS3Bucket"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Route 53 configuration
resource "aws_route53_zone" "wordpress_route53_zone" {
  name = var.route53_zone_name
  tags = {
    Name        = "WordPressRoute53Zone"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name    = var.route53_zone_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cloudfront_distribution.zone_id
    evaluate_target_health = false
  }
}

# Outputs
output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "rds_instance_endpoint" {
  value = aws_db_instance.wordpress_rds_instance.endpoint
}

output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3_bucket.bucket
}

output "route53_zone_name" {
  value = aws_route53_zone.wordpress_route53_zone.name
}
