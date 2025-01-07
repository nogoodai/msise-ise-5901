# Define the required Terraform provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.1.0"
    }
  }

  required_version = "1.3.9"
}

# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Define variables for the VPC and networking
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}
variable "availability_zones" {
  default = ["us-west-2a", "us-west-2b"]
}

# Create the VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "WordPressVPC"
  }
}

# Create subnets
resource "aws_subnet" "public_subnets" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "Public-Subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, length(var.availability_zones) + count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "Private-Subnet-${count.index + 1}"
  }
}

# Create route tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "Public-Route-Table"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "Private-Route-Table"
  }
}

# Create internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPress-IGW"
  }
}

# Associate public route table with the internet gateway
resource "aws_route" "public_internet_gateway_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Associate subnets with route tables
resource "aws_route_table_association" "public_subnets_association" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnets_association" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Define security groups
variable "web_server_security_group_name" {
  default = "WordPress-Web-Server-SG"
}
variable "database_security_group_name" {
  default = "WordPress-Database-SG"
}
variable "elb_security_group_name" {
  default = "WordPress-ELB-SG"
}

resource "aws_security_group" "web_server_sg" {
  name        = var.web_server_security_group_name
  description = "Allow inbound HTTP, HTTPS, and SSH traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH traffic"
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
    Name = var.web_server_security_group_name
  }
}

resource "aws_security_group" "database_sg" {
  name        = var.database_security_group_name
  description = "Allow inbound MySQL traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "MySQL traffic from web server"
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
    Name = var.database_security_group_name
  }
}

resource "aws_security_group" "elb_sg" {
  name        = var.elb_security_group_name
  description = "Allow inbound HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS traffic"
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
    Name = var.elb_security_group_name
  }
}

# Create the RDS instance
resource "aws_db_instance" "wordpress_db" {
  instance_class       = "db.t2.micro"
  engine               = "mysql"
  engine_version       = "8.0.28"
  multi_az             = true
  vpc_security_group_ids = [aws_security_group.database_sg.id]
  db_name                 = "wordpressdb"
  username               = "admin"
  password               = "password123"
  publicly_accessible   = false
  skip_final_snapshot    = true
}

# Create the Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.elb_sg.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  listener {
    instance_port     = 443
    instance_protocol = "https"
    lb_port           = 443
    lb_protocol       = "https"
    ssl_certificate_id = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 10
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "WordPress-ELB"
  }
}

# Create the Auto Scaling Group for the EC2 instances
resource "aws_launch_configuration" "wordpress_launch_config" {
  name            = "wordpress-launch-config"
  image_id        = "ami-0c94855ba95c71c99"
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.web_server_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello World!" > index.html
              nohup busybox httpd -f -p 80 &
              EOF
}

resource "aws_autoscaling_group" "wordpress_asg" {
  name                 = "wordpress-asg"
  launch_configuration = aws_launch_configuration.wordpress_launch_config.name
  min_size             = 1
  max_size             = 3
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 1
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id
}

# Create the CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cdn" {
  enabled = true

  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }

  default_CACHE-behavior {
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

# Create the S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_static_assets" {
  bucket = "wordpress-static-assets-123456789012"
  acl    = "private"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Name = "WordPress-Static-Assets"
  }
}

# Create the Route 53 hosted zone
resource "aws_route53_zone" "wordpress_domain" {
  name = "example.com"
}

# Create the Route 53 record for the ELB
resource "aws_route53_record" "wordpress_elb_record" {
  zone_id = aws_route53_zone.wordpress_domain.zone_id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

# Create the CloudWatch dashboard
resource "aws_cloudwatch_dashboard" "wordpress_dashboard" {
  dashboard_name = "WordPress-Dashboard"

  dashboard_body = jsonencode([
    {
      type = "metric"
      properties = {
        metrics = [
          ["AWS/RDS/DatabaseConnections", "Sum", "DatabaseConnections", aws_db_instance.wordpress_db.id],
          ["AWS/RDS/ReadLatency", "Average", "ReadLatency", aws_db_instance.wordpress_db.id],
          ["AWS/RDS/WriteLatency", "Average", "WriteLatency", aws_db_instance.wordpress_db.id],
        ]
        period = 300
        region = "us-west-2"
        stat   = "Average"
        title  = "RDS Metrics"
      }
    },
    {
      type = "metric"
      properties = {
        metrics = [
          ["AWS/ELB/HTTPCode_Backend_2XX", "Sum", "HTTPCode_Backend_2XX", aws_elb.wordpress_elb.name],
          ["AWS/ELB/HTTPCode_Backend_4XX", "Sum", "HTTPCode_Backend_4XX", aws_elb.wordpress_elb.name],
          ["AWS/ELB/HTTPCode_Backend_5XX", "Sum", "HTTPCode_Backend_5XX", aws_elb.wordpress_elb.name],
        ]
        period = 300
        region = "us-west-2"
        stat   = "Sum"
        title  = "ELB Metrics"
      }
    },
  ])
}

output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cdn.domain_name
}

output "wordpress_route53_record_name" {
  value = aws_route53_record.wordpress_elb_record.name
}

output "wordpress_rds_instance_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_static_assets.bucket
}

output "wordpress_cloudwatch_dashboard_name" {
  value = aws_cloudwatch_dashboard.wordpress_dashboard.dashboard_name
}
