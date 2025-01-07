provider "aws" {
  region = "us-west-2"
  version = "4.67.0"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type = list(string)
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "wordpress_instance_type" {
  default = "t2.micro"
}

variable "wordpress_instance_key_pair" {
  default = "wordpress-key-pair"
}

variable "wordpress_db_instance_class" {
  default = "db.t2.small"
}

variable "wordpress_db_username" {
  default = "wordpressuser"
}

variable "wordpress_db_password" {
  default = "wordpresspassword"
}

variable "elb_listener_port" {
  default = 80
}

variable "cloudfront_distribution_domain" {
  default = "example.com"
}

variable "route53_domain" {
  default = "example.com"
}

variable "route53_zone_id" {
  default = "Z1234567890"
}

# VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

# Public Subnets
resource "aws_subnet" "wordpress_public_subnets" {
  count = 2
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = var.public_subnet_cidrs[count.index]
  availability_zone = "us-west-2${count.index + 1}"
  tags = {
    Name = "WordPressPublicSubnet${count.index + 1}"
  }
}

# Private Subnets
resource "aws_subnet" "wordpress_private_subnets" {
  count = 2
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = var.private_subnet_cidrs[count.index]
  availability_zone = "us-west-2${count.index + 1}"
  tags = {
    Name = "WordPressPrivateSubnet${count.index + 1}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "wordpress_internet_gw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressInternetGateway"
  }
}

# Route Tables
resource "aws_route_table" "wordpress_public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressPublicRouteTable"
  }
}

resource "aws_route" "wordpress_public_route" {
  route_table_id = aws_route_table.wordpress_public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.wordpress_internet_gw.id
}

resource "aws_route_table" "wordpress_private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressPrivateRouteTable"
  }
}

# Associate Public Subnets with Public Route Table
resource "aws_route_table_association" "wordpress_public_subnets_association" {
  count = 2
  subnet_id = aws_subnet.wordpress_public_subnets[count.index].id
  route_table_id = aws_route_table.wordpress_public_route_table.id
}

# Associate Private Subnets with Private Route Table
resource "aws_route_table_association" "wordpress_private_subnets_association" {
  count = 2
  subnet_id = aws_subnet.wordpress_private_subnets[count.index].id
  route_table_id = aws_route_table.wordpress_private_route_table.id
}

# Security Groups
resource "aws_security_group" "wordpress_ec2_sg" {
  name = "WordPressEC2SecurityGroup"
  description = "Allow inbound traffic on ports 80 and 22"
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port = 80
    to_port = 80
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

resource "aws_security_group" "wordpress_rds_sg" {
  name = "WordPressRDSSecurityGroup"
  description = "Allow inbound traffic on port 3306 from EC2 instances"
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    security_groups = [aws_security_group.wordpress_ec2_sg.id]
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

resource "aws_security_group" "wordpress_elb_sg" {
  name = "WordPressELBSecurityGroup"
  description = "Allow inbound traffic on ports 80 and 443"
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
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "WordPressELBSecurityGroup"
  }
}

# EC2 Instances for WordPress
resource "aws_instance" "wordpress_instances" {
  count = 2
  ami = "ami-0c94855ba95c71c99"
  instance_type = var.wordpress_instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_ec2_sg.id]
  key_name = var.wordpress_instance_key_pair
  subnet_id = aws_subnet.wordpress_public_subnets[count.index].id
  tags = {
    Name = "WordPressInstance${count.index + 1}"
  }
}

# RDS Instance for WordPress Database
resource "aws_db_instance" "wordpress_rds_instance" {
  identifier = "wordpress-rds-instance"
  instance_class = var.wordpress_db_instance_class
  engine = "mysql"
  engine_version = "8.0.28"
  publicly_accessible = false
  vpc_security_group_ids = [aws_security_group.wordpress_rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  username = var.wordpress_db_username
  password = var.wordpress_db_password
  tags = {
    Name = "WordPressRDSInstance"
  }
}

resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name = "wordpress-rds-subnet-group"
  subnet_ids = [aws_subnet.wordpress_private_subnets[0].id, aws_subnet.wordpress_private_subnets[1].id]
  tags = {
    Name = "WordPressRDSSubnetGroup"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name = "wordpress-elb"
  subnets = aws_subnet.wordpress_public_subnets.*.id
  security_groups = [aws_security_group.wordpress_elb_sg.id]
  listener {
    instance_port = 80
    instance_protocol = "http"
    lb_port = 80
    lb_protocol = "http"
  }
  tags = {
    Name = "WordPressELB"
  }
}

# Auto Scaling Group for EC2 Instances
resource "aws_autoscaling_group" "wordpress_autoscaling_group" {
  name = "wordpress-autoscaling-group"
  max_size = 2
  min_size = 1
  desired_capacity = 2
  launch_configuration = aws_launch_configuration.wordpress_launch_configuration.name
  vpc_zone_identifier = aws_subnet.wordpress_public_subnets[0].id
  tags = [
    {
      key = "Name"
      value = "WordPressAutoScalingGroup"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name = "wordpress-launch-configuration"
  image_id = "ami-0c94855ba95c71c99"
  instance_type = var.wordpress_instance_type
  security_groups = [aws_security_group.wordpress_ec2_sg.id]
  key_name = var.wordpress_instance_key_pair
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cloudfront_distribution" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id = "WordPressELB"
    custom_origin_config {
      http_port = 80
      https_port = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols = ["SSLv3", "TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  enabled = true
  is_ipv6_enabled = true
  default_root_object = "index.html"
  aliases = [var.cloudfront_distribution_domain]
  viewer_certificate {
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method = "sni-only"
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

# S3 Bucket for Static Assets
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = "wordpress-static-assets"
  acl = "private"
  force_destroy = true
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress_route53_zone" {
  name = var.route53_domain
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name = var.route53_domain
  type = "A"
  alias {
    name = aws_elb.wordpress_elb.dns_name
    zone_id = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_cloudfront_distribution_domain" {
  value = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3_bucket.id
}
