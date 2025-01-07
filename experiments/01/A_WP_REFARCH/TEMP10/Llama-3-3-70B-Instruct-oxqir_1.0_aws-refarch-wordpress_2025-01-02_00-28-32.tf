# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
}

# VPC and networking resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
}

resource "aws_subnet" "public_subnet" {
  count = 2
  cidr_block = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, count.index)
  vpc_id     = aws_vpc.wordpress_vpc.id
  availability_zone = "us-west-2${count.index + 1}"
  tags = {
    Name = "PublicSubnet${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnet" {
  count = 2
  cidr_block = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, count.index + 2)
  vpc_id     = aws_vpc.wordpress_vpc.id
  availability_zone = "us-west-2${count.index + 1}"
  tags = {
    Name = "PrivateSubnet${count.index + 1}"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

resource "aws_route_table_association" "public_route_table_association" {
  count = length(aws_subnet.public_subnet)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_route_table_association" {
  count = length(aws_subnet.private_subnet)
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security groups for EC2 instances, RDS, and ELB
resource "aws_security_group" "web_server_security_group" {
  name        = "WebServerSecurityGroup"
  description = "Allow HTTP, HTTPS, and SSH"
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
    cidr_blocks = ["192.168.1.0/24"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "WebServerSecurityGroup"
  }
}

resource "aws_security_group" "rds_security_group" {
  name        = "DBSecurityGroup"
  description = "Allow MySQL"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
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
    Name = "DBSecurityGroup"
  }
}

resource "aws_security_group" "elb_security_group" {
  name        = "ELBSecurityGroup"
  description = "Allow HTTP, HTTPS"
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
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "ELBSecurityGroup"
  }
}

# EC2 instances for WordPress
resource "aws_instance" "wordpress_instance" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.web_server_security_group.id]
  subnet_id = aws_subnet.public_subnet[0].id
  key_name = "wordpress_key"
  user_data = file("./wordpress.sh")
  tags = {
    Name = "WordPressInstance"
  }
}

# RDS instance for WordPress database
resource "aws_db_instance" "wordpress_database" {
  identifier        = "wordpress-database"
  instance_class    = "db.t2.micro"
  engine            = "mysql"
  engine_version    = "5.7"
  username          = "wordpress_user"
  password          = "wordpress_password"
  parameter_group_name = "default.mysql5.7"
  db_subnet_group_name = "wordpress-database-subnet-group"
  vpc_security_group_ids = [aws_security_group.rds_security_group.id]
  storage_type = "gp2"
  allocated_storage = 20
  backup_retention_period = 30
  skip_final_snapshot = true
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = aws_subnet.public_subnet[*].id
  security_groups = [aws_security_group.elb_security_group.id]
  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
  tags = {
    Name = "WordPressELB"
  }
}

# Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_autoscaling_group" {
  name                 = "WordPressAutoScalingGroup"
  launch_configuration = "WordPressLaunchConfiguration"
  max_size             = 5
  min_size             = 2
  vpc_zone_identifier  = aws_subnet.public_subnet[0].id
  health_check_type    = "ELB"
}

resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name          = "WordPressLaunchConfiguration"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.web_server_security_group.id]
  key_name = "wordpress_key"
  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront distribution for content delivery
resource "aws_cloudfront_distribution" "wordpress_cloudfront" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressELBOrigin"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "match-viewer"
      origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases = ["www.example.com"]
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WordPressELBOrigin"
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
    ssl_support_method = "sni-only"
  }
}

# S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-static-assets"
  acl    = "private"
  region = "us-west-2"
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
}

# Route 53 DNS configuration
resource "aws_route53_zone" "example_com" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.example_com.id
  name    = "www.example.com"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cloudfront.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cloudfront.zone_id
    evaluate_target_health = false
  }
}

# CloudWatch dashboards and metrics
resource "aws_cloudwatch_dashboard" "wordpress_dashboard" {
  dashboard_name = "WordPressDashboard"
  dashboard_body = <<EOF
{
  "widgets": [
    {
      "type": "metric",
      "x": 0,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "view": "timeSeries",
        "stacked": false,
        "metrics": [
          {
            "metricName": "CPUUtilization",
            "namespace": "AWS/EC2",
            "dimensions": [
              {
                "name": "InstanceId",
                "value": "${aws_instance.wordpress_instance.id}"
              }
            ],
            "period": 300,
            "stat": "Average",
            "unit": "Percent"
          }
        ],
        "title": "CPU Utilization",
        "region": "us-west-2"
      }
    }
  ]
}
EOF
}

resource "aws_cloudwatch_metric_alarm" "wordpress_alarm" {
  alarm_name          = "WordPressAlarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "50"
  alarm_description   = "Alarm when CPU utilization exceeds 50%"
  actions_enabled     = true
  alarm_actions       = ["arn:aws:sns:us-west-2:123456789012:WordPressTopic"]
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.wordpress_cloudfront.id
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_bucket.id
}

output "route53_record_name" {
  value = aws_route53_record.wordpress_record.name
}

output "ec2_instance_id" {
  value = aws_instance.wordpress_instance.id
}

output "rds_instance_id" {
  value = aws_db_instance.wordpress_database.id
}
