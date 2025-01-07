# Provider configuration
provider "aws" {
  region = "us-west-2"
  version = "5.1.0"
}

# Variables
variable "wordpress_vpc_cidr" {
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

variable "database_username" {
  default = "wordpress_user"
}

variable "database_password" {
  sensitive = true
}

variable "instance_type" {
  default = "t2.micro"
}

variable "ami_id" {
  default = "ami-0c94855ba95c71c99"
}

variable "key_pair_name" {
  default = "wordpress_key"
}

variable "domain_name" {
  default = "example.com"
}

# VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.wordpress_vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

# Subnets
resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnets)
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = var.public_subnets[count.index]
  availability_zone = "us-west-2${count.index % 2 + 1}"
  tags = {
    Name = "PublicSubnet${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnets)
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = var.private_subnets[count.index]
  availability_zone = "us-west-2${count.index % 2 + 1}"
  tags = {
    Name = "PrivateSubnet${count.index + 1}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Route Tables
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public_subnet_association" {
  count = length(var.public_subnets)
  subnet_id = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_subnet_association" {
  count = length(var.private_subnets)
  subnet_id = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

# Security Groups
resource "aws_security_group" "wordpress_sg" {
  name        = "wordpress_sg"
  description = "Security Group for WordPress"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
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
}

resource "aws_security_group" "database_sg" {
  name        = "database_sg"
  description = "Security Group for Database"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "MySQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Instances
resource "aws_instance" "wordpress" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  subnet_id = aws_subnet.public_subnets[0].id
  key_name = var.key_pair_name

  tags = {
    Name = "WordPressInstance"
  }
}

# RDS Instance
resource "aws_db_instance" "wordpress_db" {
  identifier = "wordpress-db"
  instance_class = "db.t2.micro"
  engine = "mysql"
  engine_version = "8.0.23"
  username = var.database_username
  password = var.database_password
  vpc_security_group_ids = [aws_security_group.database_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  skip_final_snapshot = true

  tags = {
    Name = "WordPressDB"
  }
}

# DB Subnet Group
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name = "wordpress_db_subnet_group"
  subnet_ids = aws_subnet.private_subnets.*.id

  tags = {
    Name = "WordPressDBSubnetGroup"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name = "wordpress-elb"
  subnets = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_sg.id]

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

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name = "wordpress-asg"
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  min_size = 1
  max_size = 3
  vpc_zone_identifier = aws_subnet.public_subnets[0].id

  tag {
    key = "Name"
    value = "WordPressASG"
    propagate_at_launch = true
  }
}

# Launch Configuration
resource "aws_launch_configuration" "wordpress_lc" {
  name = "wordpress-lc"
  image_id = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.wordpress_sg.id]
  key_name = var.key_pair_name

  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id = "wordpress-elb"
  }

  enabled = true
  default_root_object = "index.html"

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
    cloudfront_default_certificate = true
  }
}

# S3 Bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-bucket"
  acl    = "private"

  tags = {
    Name = "WordPressBucket"
  }
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress_dns" {
  name = var.domain_name
}

resource "aws_route53_record" "wordpress_dns_record" {
  zone_id = aws_route53_zone.wordpress_dns.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = true
  }
}

# Outputs
output "instance_id" {
  value = aws_instance.wordpress.id
}

output "rds_instance_address" {
  value = aws_db_instance.wordpress_db.address
}

output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cfd.domain_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_bucket.id
}

output "route53_zone_id" {
  value = aws_route53_zone.wordpress_dns.zone_id
}
