provider "aws" {
  region = "us-west-2"
  version = "5.1.0"
}

variable "wordpress_vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type = list(string)
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "ami" {
  default = "ami-085724f5b7211bf5e"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "azs" {
  type = list(string)
  default = ["us-west-2a", "us-west-2b"]
}

variable "ssh_key_name" {
  default = "wordpress-ssh-key"
}

variable "ssh_key" {
  default = file("~/.ssh/id_rsa.pub")
}

variable "db_instance_class" {
  default = "db.t2.small"
}

variable "db_engine" {
  default = "mysql"
}

variable "db_username" {
  default = "wordpress"
}

variable "db_password" {
  default = "wordpress123"
}

variable "cache_node_type" {
  default = "cache.t2.micro"
}

variable "cache_engine" {
  default = "memcached"
}

variable "cloudfront_origin" {
  default = "origin-bucket"
}

variable "cloudfront_ssl" {
  default = true
}

# VPC
resource "aws_vpc" "wordpress" {
  cidr_block = var.wordpress_vpc_cidr
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "WordPressVPC"
  }
}

# Subnets
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)
  vpc_id = aws_vpc.wordpress.id
  cidr_block = var.public_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "PublicSubnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.wordpress.id
  cidr_block = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]
  map_public_ip_on_launch = false
  tags = {
    Name = "PrivateSubnet-${count.index + 1}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "wordpress" {
  vpc_id = aws_vpc.wordpress.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress.id
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route" "public_internet_gateway" {
  route_table_id = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.wordpress.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.wordpress.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

# Associate subnets with route tables
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)
  subnet_id = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)
  subnet_id = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security Groups
resource "aws_security_group" "wordpress" {
  name        = "wordpress-sg"
  description = "Allow inbound traffic on port 80 and 443"
  vpc_id      = aws_vpc.wordpress.id

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
    Name = "WordPressSG"
  }
}

resource "aws_security_group" "rds" {
  name        = "rds-sg"
  description = "Allow inbound traffic on port 3306"
  vpc_id      = aws_vpc.wordpress.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "RDSSG"
  }
}

resource "aws_security_group" "elb" {
  name        = "elb-sg"
  description = "Allow inbound traffic on port 80 and 443"
  vpc_id      = aws_vpc.wordpress.id

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
    Name = "ELBSG"
  }
}

# EC2 Instances
resource "aws_instance" "wordpress" {
  ami           = var.ami
  instance_type = var.instance_type
  subnet_id     = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.wordpress.id]
  key_name               = var.ssh_key_name
  tags = {
    Name = "WordPressInstance"
  }
}

# RDS Instance
resource "aws_db_instance" "wordpress" {
  allocated_storage    = 20
  engine               = var.db_engine
  engine_version       = "5.7.35"
  instance_class       = var.db_instance_class
  name                 = "wordpressdb"
  username             = var.db_username
  password             = var.db_password
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress.name
  multi_az             = true
  parameter_group_name = aws_db_parameter_group.wordpress.name
  tags = {
    Name = "WordPressRDS"
  }
}

resource "aws_db_subnet_group" "wordpress" {
  name       = "wordpress_db_subnet_group"
  subnet_ids = [aws_subnet.private[0].id, aws_subnet.private[1].id]

  tags = {
    Name = "WordPressDBSubnetGroup"
  }
}

resource "aws_db_parameter_group" "wordpress" {
  name   = "wordpress-parameter-group"
  family = "mysql5.7"

  parameter {
    name  = "character_set_server"
    value = "utf8"
  }

  parameter {
    name  = "character_set_client"
    value = "utf8"
  }

  tags = {
    Name = "WordPressParameterGroup"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress" {
  name            = "wordpress-elb"
  subnets         = [aws_subnet.public[0].id, aws_subnet.public[1].id]
  security_groups = [aws_security_group.elb.id]
  instances       = [aws_instance.wordpress.id]

  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 80
    lb_protocol        = "http"
  }

  listener {
    instance_port      = 443
    instance_protocol  = "https"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "arn:aws:iam::123456789012:server-certificate/WordPressELBCertificate"
  }

  tags = {
    Name = "WordPressELB"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress" {
  name                      = "wordpress-asg"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  launch_template {
    id      = aws_launch_template.wordpress.id
    version = aws_launch_template.wordpress.latest_version_number
  }
  target_group_arns = [aws_alb_target_group.wordpress.arn]
  vpc_zone_identifier = [aws_subnet.private[0].id, aws_subnet.private[1].id]

  tag {
    key                 = "Name"
    value               = "WordPressASG"
    propagate_at_launch = true
  }
}

resource "aws_launch_template" "wordpress" {
  name_prefix = "wordpress-launch-template"

  image_id = var.ami

  instance_type = var.instance_type

  key_name = var.ssh_key_name

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.wordpress.id]
  }

  user_data = base64encode(file("~/.aws/templates/userdata.sh"))
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress" {
  enabled = true
  is_ipv6_enabled = true
  comment = "WordPress CloudFront distribution"
  aliases = ["wordpress.example.com"]
  default_root_object = "index.html"
  price_class = "PriceClass_200"
  origin {
    domain_name = aws_alb.wordpress.dns_name
    origin_id   = "wordpressS3Origin"
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "match-viewer"
      origin_ssl_protocols     = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  default_cache_behavior {
    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]
    target_origin_id = "wordpressS3Origin"
    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "https-only"
    min_ttl                = 0
    default_ttl            = 7200
    max_ttl                = 31536000
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
  depends_on = [aws_alb.wordpress]
}

# ALB
resource "aws_alb" "wordpress" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.elb.id]
  subnets            = [aws_subnet.public[0].id, aws_subnet.public[1].id]
  tags = {
    Name = "WordPressALB"
  }
}

resource "aws_alb_target_group" "wordpress" {
  name     = "wordpress-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress.id
  deregistration_delay = 30
  health_check {
    interval            = 10
    path                = "/healthcheck"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

# CloudWatch Logs
resource "aws_cloudwatch_log_group" "wordpress" {
  name = "wordpress-log-group"
}

resource "aws_cloudwatch_log_stream" "wordpress" {
  name           = "wordpress-log-stream"
  log_group_name = aws_cloudwatch_log_group.wordpress.name
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "wordpress" {
  alarm_name          = "wordpress-metric-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Alarm for WordPress instance"
  actions_enabled     = true
  alarm_actions       = [aws_sns_topic.wordpress.arn]
  insufficient_data_actions = []
  ok_actions          = []
}

resource "aws_sns_topic" "wordpress" {
  name = "wordpress-sns-topic"
}

resource "aws_sns_topic_subscription" "wordpress" {
  topic_arn = aws_sns_topic.wordpress.arn
  protocol  = "email"
  endpoint  = "wordpress@example.com"
}

# S3 Bucket
resource "aws_s3_bucket" "wordpress" {
  bucket = "wordpress-example-bucket"
  acl    = "private"
  force_destroy = true
  versioning {
    enabled = true
  }
  tags = {
    Name = "WordPressS3Bucket"
  }
}

# Route 53
resource "aws_route53_zone" "wordpress" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress" {
  zone_id = aws_route53_zone.wordpress.id
  name    = "wordpress.example.com"
  type    = "A"
  alias {
    name                   = aws_alb.wordpress.dns_name
    zone_id               = aws_alb.wordpress.zone_id
    evaluate_target_health = true
  }
}

output "wordpress_url" {
  value = "http://${aws_alb.wordpress.dns_name}"
}

output "wordpress_rds" {
  value = aws_db_instance.wordpress.address
}

output "wordpress_s3_bucket" {
  value = aws_s3_bucket.wordpress.id
}

output "wordpress_cloudfront_distribution" {
  value = aws_cloudfront_distribution.wordpress.domain_name
}
