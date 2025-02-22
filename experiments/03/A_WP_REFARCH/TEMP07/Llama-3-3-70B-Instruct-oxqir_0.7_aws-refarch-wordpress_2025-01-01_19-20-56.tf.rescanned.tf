# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Define VPC and networking resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "WordPressVPC"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name        = "PublicSubnet"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name        = "PrivateSubnet"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnet_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

# Define security groups
resource "aws_security_group" "web_server_sg" {
  name        = "WordPressWebServerSG"
  description = "Allow inbound HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "Allow inbound HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "Allow inbound HTTPS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "Allow inbound SSH traffic"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WordPressWebServerSG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "WordPressRDSSG"
  description = "Allow inbound RDS traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "Allow inbound RDS traffic"
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
    Name        = "WordPressRDSSG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Define EC2 instances for WordPress
resource "aws_instance" "wordpress_instance" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  subnet_id = aws_subnet.public_subnet.id
  key_name = "wordpress-key"
  associate_public_ip_address = false
  monitoring = true
  ebs_optimized = true
  tags = {
    Name        = "WordPressInstance"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Define RDS instance for WordPress database
resource "aws_db_instance" "wordpress_rds" {
  identifier        = "wordpress-rds"
  instance_class    = "db.t2.micro"
  engine            = "mysql"
  engine_version    = "8.0.23"
  username          = var.rds_username
  password          = var.rds_password
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  storage_encrypted = true
  backup_retention_period = 12
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]
  iam_database_authentication_enabled = true
  tags = {
    Name        = "WordPressRDS"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = [aws_subnet.private_subnet.id]

  tags = {
    Name        = "WordPressRDSSubnetGroup"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Define Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = [aws_subnet.public_subnet.id]
  security_groups = [aws_security_group.web_server_sg.id]

  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 80
    lb_protocol        = "http"
  }

  access_logs {
    bucket        = aws_s3_bucket.wordpress_s3.id
    bucket_prefix = "elb-access-logs"
    interval      = 60
  }

  tags = {
    Name        = "WordPressELB"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Define Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = aws_subnet.public_subnet.id
  load_balancers = [aws_elb.wordpress_elb.name]

  tag {
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "Production"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = "WordPress"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.web_server_sg.id]
  key_name        = "wordpress-key"

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello World"
              EOF
}

# Define CloudFront distribution for content delivery
resource "aws_cloudfront_distribution" "wordpress_cloudfront" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WordPressELB"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "https-only"
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
    ssl_support_method  = "sni-only"
  }

  logging_config {
    bucket = aws_s3_bucket.wordpress_s3.id
    prefix = "cloudfront-access-logs"
  }

  tags = {
    Name        = "WordPressCloudFront"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Define S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_s3" {
  bucket = "wordpress-s3-bucket"
  acl    = "private"
  versioning {
    enabled = true
  }
  logging {
    target_bucket = aws_s3_bucket.wordpress_s3_access_logs.id
    target_prefix  = "/access-logs/"
  }

  tags = {
    Name        = "WordPressS3Bucket"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket" "wordpress_s3_access_logs" {
  bucket = "wordpress-s3-access-logs"
  acl    = "private"

  tags = {
    Name        = "WordPressS3AccessLogs"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Define Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_route53" {
  name = "example.com"

  tags = {
    Name        = "WordPressRoute53Zone"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53.id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_query_log" "wordpress_route53_query_log" {
  cloudwatch_log_group_arn = aws_cloudwatch_log_group.wordpress_cloudwatch_log_group.arn
  zone_id                 = aws_route53_zone.wordpress_route53.id
}

resource "aws_cloudwatch_log_group" "wordpress_cloudwatch_log_group" {
  name = "wordpress-cloudwatch-log-group"
}

# Define CloudWatch dashboards
resource "aws_cloudwatch_dashboard" "wordpress_dashboard" {
  dashboard_name = "WordPressDashboard"

  dashboard_body = <<-EOF
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
                "region": "us-west-2"
              }
            ],
            "period": 300,
            "stat": "Average",
            "title": "CPU Utilization",
            "yAxis": {
              "left": {
                "min": 0,
                "max": 100
              }
            }
          }
        }
      ]
    }
  EOF
}

variable "rds_username" {
  type        = string
  default     = "wordpress"
  sensitive   = true
}

variable "rds_password" {
  type        = string
  default     = "wordpress"
  sensitive   = true
}

output "wordpress_elb_dns_name" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "The DNS name of the WordPress ELB"
}

output "wordpress_rds_endpoint" {
  value       = aws_db_instance.wordpress_rds.endpoint
  description = "The endpoint of the WordPress RDS instance"
}

output "wordpress_s3_bucket_name" {
  value       = aws_s3_bucket.wordpress_s3.bucket
  description = "The name of the WordPress S3 bucket"
}

output "wordpress_route53_zone_id" {
  value       = aws_route53_zone.wordpress_route53.id
  description = "The ID of the WordPress Route 53 zone"
}

output "wordpress_cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.wordpress_cloudfront.id
  description = "The ID of the WordPress CloudFront distribution"
}
