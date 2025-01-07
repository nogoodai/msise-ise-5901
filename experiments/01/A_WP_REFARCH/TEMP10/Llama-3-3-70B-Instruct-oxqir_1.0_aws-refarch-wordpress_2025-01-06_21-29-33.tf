# Terraform configuration for WordPress architecture on AWS

# Specify the provider and version
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 4.64.0"
    }
  }
}

# Define provider configuration
provider "aws" {
  region = "us-west-2"
}

# Define variables
variable "vpc_cidr_block" {
  type    = string
  default = "10.0.0.0/16"
}

variable "vpc_name" {
  type    = string
  default = "WordPressVPC"
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

variable "ami_id" {
  type = string
}

variable "db_instance_class" {
  type    = string
  default = "db.t2.small"
}

variable "db_engine" {
  type    = string
  default = "mysql"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "domain_name" {
  type = string
}

# Create VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name        = var.vpc_name
    Environment = "production"
  }
}

# Create subnets
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name        = "Public Subnet"
    Environment = "production"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name        = "Private Subnet"
    Environment = "production"
  }
}

# Create internet gateway
resource "aws_internet_gateway" "wordpress_gateway" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPress Gateway"
    Environment = "production"
  }
}

# Create route tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "Public Route Table"
    Environment = "production"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_gateway.id
}

resource "aws_route_table_association" "public_route_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

# Create security groups
resource "aws_security_group" "web_server_security_group" {
  name        = "WordPressWebServerSecurityGroup"
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
    Name        = "WordPress Web Server Security Group"
    Environment = "production"
  }
}

resource "aws_security_group" "db_security_group" {
  name        = "WordPressDBSecurityGroup"
  description = "Allow inbound MySQL traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "Allow inbound MySQL traffic"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.web_server_security_group.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WordPress DB Security Group"
    Environment = "production"
  }
}

# Create RDS instance
resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = var.db_engine
  engine_version       = "8.0.28"
  instance_class       = var.db_instance_class
  name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = var.db_password
  parameter_group_name = "default.mysql8.0"
  vpc_security_group_ids = [aws_security_group.db_security_group.id]
  db_subnet_group_name    = aws_db_subnet_group.wordpress_db_subnet.name
  skip_final_snapshot     = true
}

resource "aws_db_subnet_group" "wordpress_db_subnet" {
  name       = "wordpress_db_subnet"
  subnet_ids = [aws_subnet.private_subnet.id]

  tags = {
    Name        = "WordPress DB Subnet Group"
    Environment = "production"
  }
}

# Create EC2 instances
resource "aws_instance" "wordpress_instance" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.web_server_security_group.id]
  subnet_id = aws_subnet.private_subnet.id

  tags = {
    Name        = "WordPress Instance"
    Environment = "production"
  }
}

# Create Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = [aws_subnet.public_subnet.id]
  security_groups = [aws_security_group.web_server_security_group.id]

  listener {
    instance_port      = 80
    instance_protocol = "http"
    lb_port            = 80
    lb_protocol        = "http"
  }

  tags = {
    Name        = "WordPress ELB"
    Environment = "production"
  }
}

# Create Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_autoscaling" {
  name                 = "wordpress-autoscaling"
  max_size             = 5
  min_size             = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete         = true
  launch_configuration = aws_launch_configuration.wordpress_launch.name
}

resource "aws_launch_configuration" "wordpress_launch" {
  name          = "wordpress-launch"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_server_security_group.id]

  lifecycle {
    create_before_destroy = true
  }
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cloudfront" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases = ["${var.domain_name}"]

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
    acm_certificate_arn = aws_acm_certificate_validation.wordpress_cert.certificate_arn
    ssl_support_method  = "sni-only"
  }
}

resource "aws_acm_certificate" "wordpress_cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"
}

resource "aws_route53_record" "wordpress_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.wordpress_cert.domain_validation_options : dvo.domain_name => {
      name    = dvo.resource_record_name
      record  = dvo.resource_record_value
      type    = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.wordpress_zone.id
}

resource "aws_acm_certificate_validation" "wordpress_cert" {
  certificate_arn = aws_acm_certificate.wordpress_cert.arn
  validation_record {
    name    = aws_route53_record.wordpress_cert_validation["${aws_acm_certificate.wordpress_cert.domain_name}"].name
    type    = aws_route53_record.wordpress_cert_validation["${aws_acm_certificate.wordpress_cert.domain_name}"].type
    value   = aws_route53_record.wordpress_cert_validation["${aws_acm_certificate.wordpress_cert.domain_name}"].records[0]
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
}

# Create S3 bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = var.domain_name
  acl    = "private"

  tags = {
    Name        = "WordPress Bucket"
    Environment = "production"
  }
}

# Create Route 53 record
resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cloudfront.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cloudfront.zone_id
    evaluate_target_health = false
  }
}

# Create CloudWatch dashboard
resource "aws_cloudwatch_dashboard" "wordpress_dashboard" {
  dashboard_name = "WordPress Dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type       = "metric"
        x          = 0
        y          = 0
        width      = 12
        height     = 6
        properties = {
          view = "timeSeries"
          stacked = false
          metrics = [
            {
              label = "CPUUtilization"
              id    = "cpu"
              metric = [
                "AWS/EC2",
                "CPUUtilization",
                "InstanceId",
                aws_instance.wordpress_instance.id,
              ]
              region = "us-west-2"
              period = 300
            },
          ]
          title = "CPU Utilization"
        }
      },
    ]
  })
}

output "domain_name" {
  value       = var.domain_name
  description = "The domain name of the WordPress site"
}

output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.wordpress_cloudfront.id
  description = "The ID of the CloudFront distribution"
}

output "rds_instance_id" {
  value       = aws_db_instance.wordpress_db.id
  description = "The ID of the RDS instance"
}

output "elb_dns_name" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "The DNS name of the Elastic Load Balancer"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.wordpress_bucket.id
  description = "The name of the S3 bucket"
}
