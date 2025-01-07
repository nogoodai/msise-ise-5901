terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.1.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "wordpress_instance_type" {
  default = "t2.micro"
}

variable "rds_instance_type" {
  default = "db.t2.small"
}

variable "ssh_key_name" {
  default = "wordpress-ssh-key"
}

variable "ssh_key" {
  sensitive = true
}

variable "domain_name" {
  default = "example.com"
}

variable "zone_id" {
  default = "ZXXXXXXXXXXXXXXX"
}

# Create a VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
  }
}

# Create public and private subnets
resource "aws_subnet" "public_subnet" {
  cidr_block = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, 1)
  vpc_id     = aws_vpc.wordpress_vpc.id
  availability_zone = "us-west-2a"
  map_public_ip_on_launch = true
  tags = {
    Name        = "PublicSubnet"
    Environment = "production"
  }
}

resource "aws_subnet" "private_subnet" {
  cidr_block = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, 2)
  vpc_id     = aws_vpc.wordpress_vpc.id
  availability_zone = "us-west-2a"
  tags = {
    Name        = "PrivateSubnet"
    Environment = "production"
  }
}

# Create an internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
  }
}

# Create a public route table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = "production"
  }
}

# Create a route to the internet gateway
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Associate the public route table with the public subnet
resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

# Create a private route table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = "production"
  }
}

# Associate the private route table with the private subnet
resource "aws_route_table_association" "private_subnet_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

# Create a security group for EC2 instances
resource "aws_security_group" "wordpress_sg" {
  name        = "WordPressSG"
  description = "Allow incoming HTTP, HTTPS, and SSH traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

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
    Name        = "WordPressSG"
    Environment = "production"
  }
}

# Create a security group for RDS
resource "aws_security_group" "rds_sg" {
  name        = "RDSSG"
  description = "Allow incoming MySQL traffic from EC2 instances"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "RDSSG"
    Environment = "production"
  }
}

# Create an EC2 instance for WordPress
resource "aws_instance" "wordpress_instance" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.wordpress_instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  subnet_id = aws_subnet.public_subnet.id
  key_name = var.ssh_key_name
  tags = {
    Name        = "WordPressInstance"
    Environment = "production"
  }
}

# Create an RDS instance for the WordPress database
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = var.rds_instance_type
  name                 = "wordpressdb"
  username             = "wordpress"
  password             = "wordpresspassword"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  tags = {
    Name        = "WordPressRDS"
    Environment = "production"
  }
}

# Create a DB subnet group for RDS
resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = [aws_subnet.private_subnet.id]

  tags = {
    Name        = "WordPressRDSSubnetGroup"
    Environment = "production"
  }
}

# Create an Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = [aws_subnet.public_subnet.id]
  security_groups = [aws_security_group.wordpress_sg.id]

  listener {
    lb_port       = 80
    lb_protocol   = "http"
    instance_port = 80
    instance_protocol = "http"
  }

  tags = {
    Name        = "WordPressELB"
    Environment = "production"
  }
}

# Create an Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = aws_subnet.public_subnet.id

  tag {
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }
}

# Create a launch configuration for the Auto Scaling Group
resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.wordpress_instance_type
  security_groups = [aws_security_group.wordpress_sg.id]
  key_name = var.ssh_key_name
}

# Create a CloudFront distribution for content delivery
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "S3Origin"
  }

  enabled             = true
  is_ipv6_enabled     = true
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

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Create an S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = "wordpress-static-assets"
  acl    = "public-read"

  tags = {
    Name        = "WordPressS3Bucket"
    Environment = "production"
  }
}

# Create a Route 53 DNS configuration
resource "aws_route53_record" "wordpress_dns_record" {
  zone_id = var.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = true
  }
}

output "wordpress_instance_id" {
  value = aws_instance.wordpress_instance.id
}

output "wordpress_rds_instance_id" {
  value = aws_db_instance.wordpress_rds.id
}

output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_cfd_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cfd.domain_name
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3_bucket.bucket
}

output "wordpress_dns_record_name" {
  value = aws_route53_record.wordpress_dns_record.name
}
