# Configure the AWS provider
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

# Define variables
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "subnet_cidr" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  description = "CIDR blocks for the subnets"
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

variable "cloudfront_ssl_certificate" {
  type        = string
  default     = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  description = "SSL certificate for the CloudFront distribution"
}

# Create a VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create subnets
resource "aws_subnet" "public_subnet" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.subnet_cidr[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PublicSubnet${count.index + 1}"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_subnet" "private_subnet" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnets(var.vpc_cidr, length(var.subnet_cidr), count.index + length(var.subnet_cidr))
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PrivateSubnet${count.index + 1}"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create an internet gateway
resource "aws_internet_gateway" "gateway" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "InternetGateway"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create a route table for the public subnets
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gateway.id
  }

  tags = {
    Name        = "PublicRouteTable"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Create a route table for the private subnets
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "PrivateRouteTable"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route_table_association" "private_subnet_association" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Create security groups
resource "aws_security_group" "web_server_security_group" {
  name        = "WebServerSecurityGroup"
  description = "Allow inbound HTTP and HTTPS traffic"
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
    Name        = "WebServerSecurityGroup"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_security_group" "database_security_group" {
  name        = "DatabaseSecurityGroup"
  description = "Allow inbound MySQL traffic"
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
    Name        = "DatabaseSecurityGroup"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create EC2 instances
resource "aws_instance" "wordpress_instance" {
  count         = length(var.availability_zones)
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  subnet_id     = aws_subnet.private_subnet[count.index].id
  vpc_security_group_ids = [aws_security_group.web_server_security_group.id]
  key_name               = "wordpress"

  tags = {
    Name        = "WordPressInstance${count.index + 1}"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create an RDS instance
resource "aws_db_instance" "wordpress_db" {
  identifier              = "wordpress-db"
  allocated_storage       = 20
  engine                  = "mysql"
  engine_version          = "8.0.20"
  instance_class          = var.rds_instance_class
  name                    = "wordpress_db"
  username                = "wordpress_user"
  password                = "wordpress_password"
  vpc_security_group_ids = [aws_security_group.database_security_group.id]
  multi_az               = true

  tags = {
    Name        = "WordPressDB"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create an Elastic Load Balancer
resource "aws_alb" "wordpress_alb" {
  name               = "WordPressALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_server_security_group.id]
  subnets            = aws_subnet.public_subnet.*.id

  tags = {
    Name        = "WordPressALB"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_alb_target_group" "wordpress_target_group" {
  name     = "WordPressTargetGroup"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 10
    timeout             = 5
    path                = "/healthcheck"
    interval            = 10
  }

  tags = {
    Name        = "WordPressTargetGroup"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_alb_listener" "wordpress_listener" {
  load_balancer_arn = aws_alb.wordpress_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.wordpress_target_group.arn
    type             = "forward"
  }
}

# Create an Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_autoscaling_group" {
  name                = "WordPressAutoScalingGroup"
  max_size            = 5
  min_size            = 1
  desired_capacity    = 1
  health_check_type   = "EC2"
  launch_configuration = aws_launch_configuration.wordpress_launch_configuration.name
  vpc_zone_identifier = aws_subnet.private_subnet.*.id

  tag {
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name          = "WordPressLaunchConfiguration"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_server_security_group.id]
  key_name               = "wordpress"

  user_data = file("${path.module}/user_data.sh")

  lifecycle {
    create_before_destroy = true
  }
}

# Create a CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = "wordpress-alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "match-viewer"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

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
    acm_certificate_arn = var.cloudfront_ssl_certificate
    ssl_support_method  = "sni-only"
  }

  tags = {
    Name        = "WordPressDistribution"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create an S3 bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-bucket"
  acl    = "private"

  versioning {
    enabled = true
  }

  tags = {
    Name        = "WordPressBucket"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create a Route 53 record
resource "aws_route53_record" "wordpress_record" {
  zone_id = "Z1234567890"
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_distribution.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_distribution.zone_id
    evaluate_target_health = false
  }
}

# Create a CloudWatch alarm
resource "aws_cloudwatch_metric_alarm" "wordpress_alarm" {
  alarm_name                = "WordPressAlarm"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = "2"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "300"
  statistic                  = "Average"
  threshold                 = "70"
  alarm_description         = "This metric alarm monitors the CPU utilization of the WordPress instance"
  alarm_actions             = [aws_autoscaling_policy.wordpress_scaling_policy.arn]
}

# Create an Auto Scaling policy
resource "aws_autoscaling_policy" "wordpress_scaling_policy" {
  name                   = "WordPressScalingPolicy"
  policy_type           = "StepScaling"
  resource_id           = aws_autoscaling_group.wordpress_autoscaling_group.id
  scalable_dimension    = aws_autoscaling_group.wordpress_autoscaling_group.scalable_dimension

  step_adjustment {
    scaling_adjustment          = 1
    metric_aggregation_type    = "Maximum"
    metric_interval_upper_bound = 0
  }
}

output "wordpress_alb_dns_name" {
  value = aws_alb.wordpress_alb.dns_name
}

output "wordpress_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_distribution.domain_name
}

output "wordpress_bucket_name" {
  value = aws_s3_bucket.wordpress_bucket.bucket
}
