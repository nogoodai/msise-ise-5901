# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Define variables
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnets" {
  type = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  type = list(string)
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  type = list(string)
  default = ["us-west-2a", "us-west-2b"]
}

variable "instance_type" {
  default = "t2.micro"
}

variable "ami_id" {
  default = "ami-0c55b159cbfafe1f0"
}

variable "rds_instance_class" {
  default = "db.t2.small"
}

variable "rds_engine" {
  default = "mysql"
}

variable "rds_username" {
  default = "admin"
}

variable "rds_password" {
  default = "password123"
}

variable "cloudfront_ssl_certificate" {
  default = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
}

variable "route53_domain_name" {
  default = "example.com"
}

# Create a VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

# Create public subnets
resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnets)
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = var.public_subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PublicSubnet${count.index + 1}"
  }
}

# Create private subnets
resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnets)
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = var.private_subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PrivateSubnet${count.index + 1}"
  }
}

# Create an internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Create a public route table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicRouteTable"
  }
}

# Create a route to the internet gateway
resource "aws_route" "public_route" {
  route_table_id = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.wordpress_igw.id
}

# Associate public subnets with the public route table
resource "aws_route_table_association" "public_subnets_association" {
  count = length(aws_subnet.public_subnets)
  subnet_id = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Create a private route table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

# Associate private subnets with the private route table
resource "aws_route_table_association" "private_subnets_association" {
  count = length(aws_subnet.private_subnets)
  subnet_id = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Create a security group for EC2 instances
resource "aws_security_group" "ec2_security_group" {
  name = "WordPressEC2SecurityGroup"
  description = "Allow inbound HTTP/HTTPS and SSH traffic"
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "WordPressEC2SecurityGroup"
  }
}

# Create a security group for RDS
resource "aws_security_group" "rds_security_group" {
  name = "WordPressRDSSecurityGroup"
  description = "Allow inbound MySQL traffic from EC2 instances"
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    security_groups = [aws_security_group.ec2_security_group.id]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "WordPressRDSSecurityGroup"
  }
}

# Create an RDS instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage = 20
  engine = var.rds_engine
  engine_version = "5.7"
  instance_class = var.rds_instance_class
  vpc_security_group_ids = [aws_security_group.rds_security_group.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  username = var.rds_username
  password = var.rds_password
  parameter_group_name = aws_db_parameter_group.wordpress_db_parameter_group.name
  skip_final_snapshot = true
  tags = {
    Name = "WordPressRDS"
  }
}

# Create a DB subnet group
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name = "WordPressDBSubnetGroup"
  subnet_ids = aws_subnet.private_subnets.*.id
  tags = {
    Name = "WordPressDBSubnetGroup"
  }
}

# Create a DB parameter group
resource "aws_db_parameter_group" "wordpress_db_parameter_group" {
  name = "WordPressDBParameterGroup"
  family = "mysql5.7"
  parameter {
    name = "character_set_server"
    value = "utf8"
  }
  parameter {
    name = "collation_server"
    value = "utf8_unicode_ci"
  }
  tags = {
    Name = "WordPressDBParameterGroup"
  }
}

# Create an Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name = "WordPressELB"
  subnets = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.ec2_security_group.id]
  listener {
    lb_port = 80
    lb_protocol = "http"
    instance_port = 80
    instance_protocol = "http"
  }
  listener {
    lb_port = 443
    lb_protocol = "https"
    instance_port = 80
    instance_protocol = "http"
    ssl_certificate_id = var.cloudfront_ssl_certificate
  }
  tags = {
    Name = "WordPressELB"
  }
}

# Create an Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_autoscaling_group" {
  name = "WordPressAutoScalingGroup"
  max_size = 5
  min_size = 1
  launch_configuration = aws_launch_configuration.wordpress_launch_configuration.name
  vpc_zone_identifier = aws_subnet.public_subnets.*.id
  load_balancers = [aws_elb.wordpress_elb.name]
  tags = {
    Name = "WordPressAutoScalingGroup"
  }
}

# Create a launch configuration
resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name = "WordPressLaunchConfiguration"
  image_id = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.ec2_security_group.id]
  key_name = "wordpress"
  user_data = "#!/bin/bash\nsudo apt-get update\nsudo apt-get install -y apache2\nsudo service apache2 start"
  lifecycle {
    create_before_destroy = true
  }
}

# Create a CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cloudfront_distribution" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id = "WordPressELB"
  }
  enabled = true
  is_ipv6_enabled = true
  default_root_object = "index.html"
  aliases = [var.route53_domain_name]
  viewer_certificate {
    acm_certificate_arn = var.cloudfront_ssl_certificate
    ssl_support_method = "sni-only"
  }
  default_cache_behavior {
    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods = ["GET", "HEAD"]
    target_origin_id = "WordPressELB"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "allow-all"
    min_ttl = 0
    default_ttl = 3600
    max_ttl = 86400
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  tags = {
    Name = "WordPressCloudFrontDistribution"
  }
}

# Create an S3 bucket
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = "wordpress-bucket"
  acl = "private"
  force_destroy = true
  tags = {
    Name = "WordPressS3Bucket"
  }
}

# Create a Route 53 hosted zone
resource "aws_route53_zone" "wordpress_route53_zone" {
  name = var.route53_domain_name
  tags = {
    Name = "WordPressRoute53Zone"
  }
}

# Create a Route 53 record for the ELB
resource "aws_route53_record" "wordpress_elb_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name = var.route53_domain_name
  type = "A"
  alias {
    name = aws_elb.wordpress_elb.dns_name
    zone_id = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

# Create a Route 53 record for the CloudFront distribution
resource "aws_route53_record" "wordpress_cloudfront_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name = var.route53_domain_name
  type = "A"
  alias {
    name = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
    zone_id = aws_cloudfront_distribution.wordpress_cloudfront_distribution.zone_id
    evaluate_target_health = false
  }
}

# Output the ELB DNS name
output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

# Output the CloudFront distribution domain name
output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
}

# Output the RDS instance endpoint
output "rds_instance_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

# Output the S3 bucket name
output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3_bucket.id
}

# Output the Route 53 hosted zone ID
output "route53_hosted_zone_id" {
  value = aws_route53_zone.wordpress_route53_zone.id
}
