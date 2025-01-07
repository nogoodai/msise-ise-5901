provider "aws" {
  region = "us-west-2"
  required_providers {
    aws = ">= 5.1.0"
  }
}

# VPC and Networking Resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "10.0.0.0/16"
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

resource "aws_subnet" "wordpress_public_subnet" {
  count = 2
  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = "10.0.${count.index}.0/24"
  availability_zone = "us-west-2${count.index + 1}"
  tags = {
    Name = "WordPressPublicSubnet${count.index + 1}"
  }
}

resource "aws_subnet" "wordpress_private_subnet" {
  count = 2
  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = "10.0.${count.index + 4}.0/24"
  availability_zone = "us-west-2${count.index + 1}"
  tags = {
    Name = "WordPressPrivateSubnet${count.index + 1}"
  }
}

resource "aws_route_table" "wordpress_public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressPublicRouteTable"
  }
}

resource "aws_route_table" "wordpress_private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressPrivateRouteTable"
  }
}

resource "aws_route" "wordpress_public_internet_gateway" {
  route_table_id         = aws_route_table.wordpress_public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table_association" "wordpress_public_subnet_association" {
  count          = 2
  subnet_id      = aws_subnet.wordpress_public_subnet[count.index].id
  route_table_id = aws_route_table.wordpress_public_route_table.id
}

resource "aws_route_table_association" "wordpress_private_subnet_association" {
  count          = 2
  subnet_id      = aws_subnet.wordpress_private_subnet[count.index].id
  route_table_id = aws_route_table.wordpress_private_route_table.id
}

# Security Groups
resource "aws_security_group" "wordpress_ec2_security_group" {
  name        = "WordPressEC2SecurityGroup"
  description = "Security group for WordPress EC2 instances"
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
    Name = "WordPressEC2SecurityGroup"
  }
}

resource "aws_security_group" "wordpress_rds_security_group" {
  name        = "WordPressRDSSecurityGroup"
  description = "Security group for WordPress RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
    security_groups = [aws_security_group.wordpress_ec2_security_group.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WordPressRDSSecurityGroup"
  }
}

# EC2 Instances for WordPress
resource "aws_instance" "wordpress_ec2_instance" {
  count         = 2
  ami           = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.wordpress_ec2_security_group.id]
  subnet_id = aws_subnet.wordpress_private_subnet[count.index].id
  key_name = "wordpress_key"
  tags = {
    Name = "WordPressEC2Instance${count.index + 1}"
  }
}

# RDS Instance for WordPress
resource "aws_db_instance" "wordpress_rds_instance" {
  identifier        = "wordpress-rds-instance"
  instance_class    = "db.t2.small"
  engine            = "mysql"
  engine_version    = "8.0.28"
  name              = "wordpressdb"
  username          = "admin"
  password          = "password123"
  publicly_accessible = false
  vpc_security_group_ids = [aws_security_group.wordpress_rds_security_group.id]
  db_subnet_group_name    = aws_db_subnet_group.wordpress_rds_subnet_group.name
  tags = {
    Name = "WordPressRDSInstance"
  }
}

resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = aws_subnet.wordpress_private_subnet[*].id
  tags = {
    Name = "WordPressRDSSubnetGroup"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.wordpress_public_subnet[*].id
  security_groups = [aws_security_group.wordpress_ec2_security_group.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  listener {
    instance_port      = 443
    instance_protocol  = "https"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  }

  tags = {
    Name = "WordPressELB"
  }
}

# Auto Scaling Group for EC2 Instances
resource "aws_autoscaling_group" "wordpress_autoscaling_group" {
  name                      = "wordpress-autoscaling-group"
  max_size                  = 5
  min_size                  = 2
  desired_capacity          = 2
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_launch_configuration.name
  vpc_zone_identifier       = aws_subnet.wordpress_private_subnet[*].id
  tags = {
    Name = "WordPressAutoScalingGroup"
  }
}

resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name          = "wordpress-launch-configuration"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.wordpress_ec2_security_group.id]
  key_name               = "wordpress_key"
  user_data              = file("wordpress_user_data.sh")
  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cloudfront_distribution" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }

  enabled = true

  default_root_object = "index.html"

  aliases = ["example.com", "www.example.com"]

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
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = "wordpress-s3-bucket"
  acl    = "private"

  versioning {
    enabled = true
  }

  tags = {
    Name = "WordPressS3Bucket"
  }
}

# Route 53 DNS Configuration
resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cloudfront_distribution.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "wordpress_route53_zone" {
  name = "example.com"
}

output "wordpress_vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_rds_instance_endpoint" {
  value = aws_db_instance.wordpress_rds_instance.endpoint
}

output "wordpress_cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.wordpress_cloudfront_distribution.id
}

output "wordpress_s3_bucket_arn" {
  value = aws_s3_bucket.wordpress_s3_bucket.arn
}

output "wordpress_route53_zone_id" {
  value = aws_route53_zone.wordpress_route53_zone.id
}
