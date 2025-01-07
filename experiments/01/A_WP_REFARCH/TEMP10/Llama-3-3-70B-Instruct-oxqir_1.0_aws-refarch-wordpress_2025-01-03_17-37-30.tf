# Terraform configuration

# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

# Variables
variable "vpc_cidr_block" {
  default = "10.0.0.0/16"
}

variable "public_subnets" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "instance_type" {
  default = "t2.micro"
}

variable "ami_id" {
  default = "ami-0c6746aa42b15aobao"
}

variable "rds_instance_class" {
  default = "db.t2.small"
}

variable "rds_database_name" {
  default = "wordpress"
}

variable "rds_username" {
  default = "wordpressuser"
}

variable "rds_password" {
  default = "wordpresspassword"
}

variable "cloudfront_distribution_name" {
  default = "wordpress-cloudfront"
}

variable "s3_bucket_name" {
  default = "wordpress-static-assets"
}

variable "route53_domain_name" {
  default = "example.com"
}

# VPC and networking resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name = "WordPressVPC"
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
    Name = "WordPressPublicRouteTable"
  }
}

resource "aws_route" "public_route" {
  route_table_id = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressPrivateRouteTable"
  }
}

# Subnets
resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnets)
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = var.public_subnets[count.index]
  availability_zone = "us-west-2a"
  tags = {
    Name = "WordPressPublicSubnet${count.index}"
  }
}

resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnets)
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = var.private_subnets[count.index]
  availability_zone = "us-west-2a"
  tags = {
    Name = "WordPressPrivateSubnet${count.index}"
  }
}

# Association of subnets with route tables
resource "aws_route_table_association" "public_route_table_association" {
  count = length(aws_subnet.public_subnets)
  subnet_id = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_route_table_association" {
  count = length(aws_subnet.private_subnets)
  subnet_id = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security groups for EC2 instances, RDS, and ELB
resource "aws_security_group" "ec2_security_group" {
  name = "wordpress-ec2-security-group"
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Security group for EC2 instances"
  ingress {
    protocol = "tcp"
    from_port = 80
    to_port = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    protocol = "tcp"
    from_port = 443
    to_port = 443
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    protocol = "-1"
    from_port = 0
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "WordPressEC2SecurityGroup"
  }
}

resource "aws_security_group" "rds_security_group" {
  name = "wordpress-rds-security-group"
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Security group for RDS instances"
  ingress {
    protocol = "tcp"
    from_port = 3306
    to_port = 3306
    security_groups = [aws_security_group.ec2_security_group.id]
  }
  ingress {
    protocol = "tcp"
    from_port = 443
    to_port = 443
    security_groups = [aws_security_group.ec2_security_group.id]
  }
  egress {
    protocol = "-1"
    from_port = 0
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "WordPressRDSSecurityGroup"
  }
}

resource "aws_security_group" "elb_security_group" {
  name = "wordpress-elb-security-group"
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Security group for ELB"
  ingress {
    protocol = "tcp"
    from_port = 80
    to_port = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    protocol = "tcp"
    from_port = 443
    to_port = 443
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    protocol = "-1"
    from_port = 0
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "WordPressELBSecurityGroup"
  }
}

# EC2 instances for WordPress
resource "aws_instance" "wordpress_instance" {
  ami = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.ec2_security_group.id]
  subnet_id = aws_subnet.public_subnets[0].id
  tags = {
    Name = "WordPressInstance"
  }
}

# RDS instance for WordPress
resource "aws_db_instance" "wordpress_rds_instance" {
  allocated_storage = 20
  engine = "mysql"
  engine_version = "5.7"
  instance_class = var.rds_instance_class
  db_name = var.rds_database_name
  username = var.rds_username
  password = var.rds_password
  vpc_security_group_ids = [aws_security_group.rds_security_group.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  skip_final_snapshot = true
  tags = {
    Name = "WordPressRDSInstance"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name = "wordpress-elb"
  subnets = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.elb_security_group.id]
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

# Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_autoscaling_group" {
  name = "wordpress-autoscaling-group"
  max_size = 5
  min_size = 2
  launch_configuration = aws_launch_configuration.wordpress_launch_configuration.name
  vpc_zone_identifier = aws_subnet.public_subnets[0].id
  tags = {
    Name = "WordPressAutoScalingGroup"
  }
}

resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name = "wordpress-launch-configuration"
  image_id = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.ec2_security_group.id]
  user_data = "#!/bin/bash\nsudo apt-get update\nsudo apt-get install -y apache2 php7.2-mysql\necho '<html><body><h1>Hello World</h1></body></html>' | sudo tee /var/www/html/index.html"
}

# CloudFront distribution for content delivery
resource "aws_cloudfront_distribution" "wordpress_cloudfront_distribution" {
  origin {
    domain_name = aws_s3_bucket.wordpress_s3_bucket.bucket_regional_domain_name
    origin_id = "wordpress-origin"
  }
  enabled = true
  aliases = [var.route53_domain_name]
  default_root_object = "index.html"
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.wordpress_acm_certificate.arn
    ssl_support_method = "sni-only"
  }
  tags = {
    Name = "WordPressCloudFrontDistribution"
  }
}

resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = var.s3_bucket_name
  acl = "public-read"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "PublicReadGetObject"
        Effect = "Allow"
        Principal = "*"
        Action = "s3:GetObject"
        Resource = "arn:aws:s3:::${var.s3_bucket_name}/*"
      },
    ]
  })
  tags = {
    Name = "WordPressS3Bucket"
  }
}

resource "aws_acm_certificate" "wordpress_acm_certificate" {
  domain_name = var.route53_domain_name
  validation_method = "DNS"
  tags = {
    Name = "WordPressACMCertificate"
  }
}

resource "aws_acm_certificate_validation" "wordpress_acm_certificate_validation" {
  certificate_arn = aws_acm_certificate.wordpress_acm_certificate.arn
  validation_record {
    name    = aws_route53_record.wordpress_route53_record.name
    type    = aws_route53_record.wordpress_route53_record.type
    value   = aws_route53_record.wordpress_route53_record.value
  }
}

resource "aws_route53_record" "wordpress_route53_record" {
  name    = "_acme-challenge.${var.route53_domain_name}"
  type    = "CNAME"
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  records = [aws_acm_certificate.wordpress_acm_certificate.domain_validation_options.0.resource_record_name]
  ttl     = 60
}

resource "aws_route53_zone" "wordpress_route53_zone" {
  name = var.route53_domain_name
  tags = {
    Name = "WordPressRoute53Zone"
  }
}

# Outputs
output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "ec2_instance_id" {
  value = aws_instance.wordpress_instance.id
}

output "rds_instance_id" {
  value = aws_db_instance.wordpress_rds_instance.id
}

output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.wordpress_cloudfront_distribution.id
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3_bucket.bucket
}

output "route53_zone_id" {
  value = aws_route53_zone.wordpress_route53_zone.id
}
