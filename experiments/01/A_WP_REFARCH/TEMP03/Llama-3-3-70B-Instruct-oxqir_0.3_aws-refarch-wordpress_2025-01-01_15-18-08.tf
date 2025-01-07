# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.1.0"
    }
  }
}

# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
}

# VPC configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "WordPressVPC"
  }
}

# Subnets
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name = "PublicSubnet"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name = "PrivateSubnet"
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
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicRouteTable"
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

# Security Groups
resource "aws_security_group" "web_server_sg" {
  name        = "WordPressWebServerSG"
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
}

resource "aws_security_group" "rds_sg" {
  name        = "WordPressRDSSG"
  description = "Allow inbound MySQL traffic from web server"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 instances for WordPress
resource "aws_instance" "wordpress_instance" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  vpc_security_group_ids = [
    aws_security_group.web_server_sg.id
  ]
  subnet_id = aws_subnet.public_subnet.id
  key_name               = "wordpress_key"
  user_data              = file("${path.module}/wordpress_setup.sh")

  tags = {
    Name = "WordPressInstance"
  }
}

# RDS instance for WordPress database
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = "db.t2.micro"
  name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = "wordpresspassword"
  vpc_security_group_ids = [
    aws_security_group.rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  skip_final_snapshot  = true
}

resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress_rds_subnet_group"
  subnet_ids = [aws_subnet.private_subnet.id]

  tags = {
    Name = "WordPressRDSSubnetGroup"
  }
}

# Elastic Load Balancer
resource "aws_lb" "wordpress_elb" {
  name               = "WordPressELB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_server_sg.id]
  subnets            = [aws_subnet.public_subnet.id]

  tags = {
    Name = "WordPressELB"
  }
}

resource "aws_lb_target_group" "wordpress_tg" {
  name     = "WordPressTG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 10
    timeout             = 5
    path                = "/"
    interval            = 10
  }
}

resource "aws_lb_listener" "wordpress_listener" {
  load_balancer_arn = aws_lb.wordpress_elb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
    type             = "forward"
  }
}

# Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "WordPressASG"
  max_size            = 5
  min_size            = 1
  desired_capacity    = 1
  vpc_zone_identifier = aws_subnet.public_subnet.id

  launch_template {
    id      = aws_launch_template.wordpress_lt.id
    version = "$Latest"
  }
}

resource "aws_launch_template" "wordpress_lt" {
  name          = "WordPressLT"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  key_name      = "wordpress_key"
  vpc_security_group_ids = [
    aws_security_group.web_server_sg.id
  ]

  user_data = base64encode(file("${path.module}/wordpress_setup.sh"))
}

# CloudFront distribution for content delivery
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_lb.wordpress_elb.dns_name
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

# S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_s3" {
  bucket = "wordpress-static-assets"
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
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_r53" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress_r53_record" {
  zone_id = aws_route53_zone.wordpress_r53.zone_id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_lb.wordpress_elb.dns_name
    zone_id               = aws_lb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

# CloudWatch logs and alarms
resource "aws_cloudwatch_log_group" "wordpress_cw_log_group" {
  name = "WordPressCWLogGroup"
}

resource "aws_cloudwatch_log_stream" "wordpress_cw_log_stream" {
  name           = "WordPressCWLogStream"
  log_group_name = aws_cloudwatch_log_group.wordpress_cw_log_group.name
}

resource "aws_cloudwatch_metric_alarm" "wordpress_cw_alarm" {
  alarm_name                = "WordPressCWAlarm"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = "2"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "300"
  statistic                 = "Average"
  threshold                 = "80"
  alarm_description         = "This metric alarm monitors the CPU utilization of the WordPress EC2 instance"
  actions_enabled           = true
  alarm_actions             = [aws_sns_topic.wordpress_sns_topic.arn]
  insufficient_data_actions = []
  ok_actions                = []
}

resource "aws_sns_topic" "wordpress_sns_topic" {
  name = "WordPressSNSTopic"
}

resource "aws_sns_topic_subscription" "wordpress_sns_subscription" {
  topic_arn = aws_sns_topic.wordpress_sns_topic.arn
  protocol  = "email"
  endpoint  = "example@example.com"
}

output "wordpress_elb_dns_name" {
  value = aws_lb.wordpress_elb.dns_name
}

output "wordpress_rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3.bucket
}

output "wordpress_r53_zone_id" {
  value = aws_route53_zone.wordpress_r53.zone_id
}
