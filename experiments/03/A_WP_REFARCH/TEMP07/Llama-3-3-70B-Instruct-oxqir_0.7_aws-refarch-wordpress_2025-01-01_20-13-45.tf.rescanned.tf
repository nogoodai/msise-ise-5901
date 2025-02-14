# Terraform configuration for AWS resources

# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.1.0"
    }
  }
}

# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
}

# Variables for user-configurable values
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "Availability zones for the subnets"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for the EC2 instances"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Instance class for the RDS instance"
}

variable "wordpress_domain" {
  type        = string
  description = "Domain name for the WordPress site"
}

# Create a VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "Prod"
    Project     = "WordPress"
  }
}

# Create subnets
resource "aws_subnet" "public_subnets" {
  count = 3
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = false
  tags = {
    Name        = "PublicSubnet${count.index}"
    Environment = "Prod"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private_subnets" {
  count = 3
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 3)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PrivateSubnet${count.index}"
    Environment = "Prod"
    Project     = "WordPress"
  }
}

# Create an internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "Prod"
    Project     = "WordPress"
  }
}

# Create route tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name        = "PublicRouteTable"
    Environment = "Prod"
    Project     = "WordPress"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = "Prod"
    Project     = "WordPress"
  }
}

# Associate subnets with route tables
resource "aws_route_table_association" "public_subnets_association" {
  count = 3
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnets_association" {
  count = 3
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Create security groups
resource "aws_security_group" "wordpress_sg" {
  name        = "wordpress-sg"
  description = "Security group for WordPress instances"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
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
    Name        = "WordPressSG"
    Environment = "Prod"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Security group for RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
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

  tags = {
    Name        = "RDSSG"
    Environment = "Prod"
    Project     = "WordPress"
  }
}

# Create EC2 instances for WordPress
resource "aws_instance" "wordpress_instances" {
  count = 3
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  subnet_id = aws_subnet.public_subnets[count.index].id
  key_name               = "wordpress_key"
  user_data = file("${path.module}/wordpress_install.sh")
  ebs_optimized = true
  monitoring = true
  tags = {
    Name        = "WordPressInstance${count.index}"
    Environment = "Prod"
    Project     = "WordPress"
  }
}

# Create an RDS instance for the WordPress database
resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = var.rds_instance_class
  name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = "wordpresspassword"
  parameter_group_name = "default.mysql8.0"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  storage_type         = "gp2"
  backup_retention_period = 30
  skip_final_snapshot  = true
  multi_az             = true
  storage_encrypted = true
  deletion_protection = true
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]
  tags = {
    Name        = "WordPressDB"
    Environment = "Prod"
    Project     = "WordPress"
  }
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private_subnets.*.id

  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = "Prod"
    Project     = "WordPress"
  }
}

# Create an Elastic Load Balancer
resource "aws_alb" "wordpress_alb" {
  name            = "wordpress-alb"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_sg.id]
  drop_invalid_header_fields = true
  enable_deletion_protection = true
  tags = {
    Name        = "WordPressALB"
    Environment = "Prod"
    Project     = "WordPress"
  }
}

resource "aws_alb_target_group" "wordpress_target_group" {
  name     = "wordpress-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressTargetGroup"
    Environment = "Prod"
    Project     = "WordPress"
  }
}

resource "aws_alb_listener" "wordpress_listener" {
  load_balancer_arn = aws_alb.wordpress_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"

  default_action {
    target_group_arn = aws_alb_target_group.wordpress_target_group.arn
    type             = "forward"
  }
}

# Create an Auto Scaling Group for the EC2 instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  max_size                  = 5
  min_size                  = 3
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity          = 3
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_launch_config.name
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id
  load_balancers = [aws_alb.wordpress_alb.name]
  tags = {
    Name        = "WordPressASG"
    Environment = "Prod"
    Project     = "WordPress"
  }
}

resource "aws_launch_configuration" "wordpress_launch_config" {
  name          = "wordpress-launch-config"
  image_id      = "ami-0c55b159cbfafe1f0"
  instance_type = var.instance_type
  security_groups = [aws_security_group.wordpress_sg.id]
  key_name               = "wordpress_key"
  user_data = file("${path.module}/wordpress_install.sh")
  ebs_optimized = true
}

# Create a CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = "wordpress-alb"
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-alb"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
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
  }

  logging_config {
    bucket = "wordpress-bucket.s3.amazonaws.com"
    prefix = "wordpress-cloudfront-logs"
  }

  tags = {
    Name        = "WordPressCloudFrontDistribution"
    Environment = "Prod"
    Project     = "WordPress"
  }
}

# Create an S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-bucket"
  acl    = "private"

  versioning {
    enabled = true
  }

  logging {
    target_bucket = "wordpress-bucket-logs"
    target_prefix = "logs/"
  }

  tags = {
    Name        = "WordPressBucket"
    Environment = "Prod"
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket" "wordpress_bucket_logs" {
  bucket = "wordpress-bucket-logs"
  acl    = "log-delivery-write"

  tags = {
    Name        = "WordPressBucketLogs"
    Environment = "Prod"
    Project     = "WordPress"
  }
}

# Create a Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_zone" {
  name = var.wordpress_domain

  tags = {
    Name        = "WordPressRoute53Zone"
    Environment = "Prod"
    Project     = "WordPress"
  }
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = var.wordpress_domain
  type    = "A"

  alias {
    name                   = aws_alb.wordpress_alb.dns_name
    zone_id               = aws_alb.wordpress_alb.zone_id
    evaluate_target_health = false
  }
}

# Create a CloudWatch dashboard
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
        "metric": "AWS/EC2/CPUCreditBalance",
        "view": "timeSeries",
        "stacked": false,
        "region": "us-west-2",
        "title": "EC2 CPU Credit Balance",
        "period": 300,
        "stat": "Average",
        "dimensions": [
          {
            "name": "InstanceId",
            "value": "${aws_instance.wordpress_instances[0].id}"
          }
        ]
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "metric": "AWS/RDS/DatabaseConnections",
        "view": "timeSeries",
        "stacked": false,
        "region": "us-west-2",
        "title": "RDS Database Connections",
        "period": 300,
        "stat": "Average",
        "dimensions": [
          {
            "name": "DBInstanceIdentifier",
            "value": "${aws_db_instance.wordpress_db.id}"
          }
        ]
      }
    }
  ]
}
EOF
}

# Create a VPC flow log
resource "aws_flow_log" "wordpress_vpc_flow_log" {
  iam_role_arn    = "arn:aws:iam::123456789012:role/flow-log-role"
  log_destination = "arn:aws:s3:::wordpress-bucket-logs"
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.wordpress_vpc.id
}

# Output critical information
output "wordpress_alb_dns_name" {
  value = aws_alb.wordpress_alb.dns_name
  description = "The DNS name of the WordPress ALB"
}

output "wordpress_rds_instance_arn" {
  value = aws_db_instance.wordpress_db.arn
  description = "The ARN of the WordPress RDS instance"
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_bucket.id
  description = "The name of the WordPress S3 bucket"
}

output "wordpress_cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.wordpress_distribution.id
  description = "The ID of the WordPress CloudFront distribution"
}

output "wordpress_route53_zone_id" {
  value = aws_route53_zone.wordpress_zone.zone_id
  description = "The ID of the WordPress Route 53 zone"
}

output "wordpress_cloudwatch_dashboard_name" {
  value = aws_cloudwatch_dashboard.wordpress_dashboard.dashboard_name
  description = "The name of the WordPress CloudWatch dashboard"
}
