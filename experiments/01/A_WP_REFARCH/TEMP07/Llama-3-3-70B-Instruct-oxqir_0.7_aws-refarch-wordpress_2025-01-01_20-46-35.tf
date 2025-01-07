provider "aws" {
  region = "us-west-2"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnets" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  default = ["us-west-2a", "us-west-2b"]
}

variable "instance_type" {
  default = "t2.micro"
}

variable "ami_id" {
  default = "ami-0c2ab3b8efb09f272"
}

variable "wordpress_db_username" {
  default = "wordpress"
}

variable "wordpress_db_password" {
  default = "wordpress"
}

variable "wordpress_db_name" {
  default = "wordpress"
}

variable "rds_instance_class" {
  default = "db.t2.small"
}

variable "cloudfront_ssl_certificate" {
  default = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
}

variable "route53_zone_name" {
  default = "example.com"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnets)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name        = "PublicSubnet${count.index + 1}"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PrivateSubnet${count.index + 1}"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name        = "PublicRouteTable"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_route_table_association" "public_route_table_association" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_security_group" "wordpress_ec2_sg" {
  name        = "WordPressEC2SG"
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
    Name        = "WordPressEC2SG"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "wordpress_rds_sg" {
  name        = "WordPressRDSSG"
  description = "Security group for WordPress RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
    security_groups = [aws_security_group.wordpress_ec2_sg.id]
  }
  tags = {
    Name        = "WordPressRDSSG"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_instance" "wordpress_ec2" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_ec2_sg.id]
  key_name               = "wordpress"
  user_data = file("${path.module}/wordpress-install.sh")
  tags = {
    Name        = "WordPressEC2"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_db_instance" "wordpress_rds" {
  identifier        = "wordpress-rds"
  instance_class    = var.rds_instance_class
  engine            = "mysql"
  engine_version    = "8.0.28"
  username          = var.wordpress_db_username
  password          = var.wordpress_db_password
  db_name           = var.wordpress_db_name
  port              = 3306
  vpc_security_group_ids = [aws_security_group.wordpress_rds_sg.id]
  publicly_accessible = false
  multi_az = true
  tags = {
    Name        = "WordPressRDS"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_elasticache_cluster" "wordpress_elasticache" {
  cluster_id           = "wordpress-elasticache"
  engine               = "memcached"
  engine_version       = "1.6.6"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.memcached1.6"
  port                 = 11211
  tags = {
    Name        = "WordPressElasticache"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_ec2_sg.id]
  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
  listener {
    instance_port      = 443
    instance_protocol = "https"
    lb_port           = 443
    lb_protocol       = "https"
    ssl_certificate_id = var.cloudfront_ssl_certificate
  }
  tags = {
    Name        = "WordPressELB"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_alb" "wordpress_alb" {
  name            = "wordpress-alb"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_ec2_sg.id]
  tags = {
    Name        = "WordPressALB"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_alb_target_group" "wordpress_alb_target_group" {
  name     = "wordpress-alb-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressALBTargetGroup"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_alb_listener" "wordpress_alb_listener" {
  load_balancer_arn = aws_alb.wordpress_alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    target_group_arn = aws_alb_target_group.wordpress_alb_target_group.arn
    type             = "forward"
  }
  tags = {
    Name        = "WordPressALBListener"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_alb_listener" "wordpress_alb_listener_https" {
  load_balancer_arn = aws_alb.wordpress_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.cloudfront_ssl_certificate
  default_action {
    target_group_arn = aws_alb_target_group.wordpress_alb_target_group.arn
    type             = "forward"
  }
  tags = {
    Name        = "WordPressALBListenerHTTPS"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_autoscaling_group" "wordpress_ec2_asg" {
  name                = "wordpress-ec2-asg"
  launch_configuration = aws_launch_configuration.wordpress_ec2_lc.name
  min_size            = 1
  max_size            = 3
  vpc_zone_identifier = aws_subnet.public_subnets.*.id
  tags = [
    {
      key                 = "Name"
      value               = "WordPressEC2ASG"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = "production"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = "WordPress"
      propagate_at_launch = true
    },
  ]
}

resource "aws_launch_configuration" "wordpress_ec2_lc" {
  name          = "wordpress-ec2-lc"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.wordpress_ec2_sg.id]
  key_name               = "wordpress"
  user_data = file("${path.module}/wordpress-install.sh")
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudfront_distribution" "wordpress_cloudfront" {
  origin {
    domain_name = aws_s3_bucket.wordpress_s3.bucket
    origin_id   = "wordpress-s3"
  }
  enabled = true
  default_root_object = "index.html"
  aliases = [var.route53_zone_name]
  viewer_certificate {
    acm_certificate_arn = var.cloudfront_ssl_certificate
    ssl_support_method  = "sni-only"
  }
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-s3"
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
  tags = {
    Name        = "WordPressCloudFront"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket" "wordpress_s3" {
  bucket = var.route53_zone_name
  acl    = "public-read"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource = "arn:aws:s3:::${var.route53_zone_name}/*"
      },
    ]
  })
  website {
    index_document = "index.html"
  }
  tags = {
    Name        = "WordPressS3"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_route53_zone" "wordpress_route53_zone" {
  name = var.route53_zone_name
  tags = {
    Name        = "WordPressRoute53Zone"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name    = var.route53_zone_name
  type    = "A"
  alias {
    name                   = aws_alb.wordpress_alb.dns_name
    zone_id               = aws_alb.wordpress_alb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_cloudwatch_metric_alarm" "wordpress_cpu_alarm" {
  alarm_name          = "WordPressCPUAlarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Alarm for high CPU usage"
  actions_enabled     = true
  alarm_actions       = [aws_sns_topic.wordpress_sns_topic.arn]
  ok_actions          = [aws_sns_topic.wordpress_sns_topic.arn]
  insufficient_data_actions = [aws_sns_topic.wordpress_sns_topic.arn]
  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "wordpress_rds_alarm" {
  alarm_name          = "WordPressRDSAlarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Alarm for high RDS CPU usage"
  actions_enabled     = true
  alarm_actions       = [aws_sns_topic.wordpress_sns_topic.arn]
  ok_actions          = [aws_sns_topic.wordpress_sns_topic.arn]
  insufficient_data_actions = [aws_sns_topic.wordpress_sns_topic.arn]
  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "wordpress_disk_alarm" {
  alarm_name          = "WordPressDiskAlarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DiskSpaceUtilization"
  namespace           = "AWS/EBS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Alarm for high disk usage"
  actions_enabled     = true
  alarm_actions       = [aws_sns_topic.wordpress_sns_topic.arn]
  ok_actions          = [aws_sns_topic.wordpress_sns_topic.arn]
  insufficient_data_actions = [aws_sns_topic.wordpress_sns_topic.arn]
  treat_missing_data = "notBreaching"
}

resource "aws_sns_topic" "wordpress_sns_topic" {
  name = "WordPressSNSTopic"
  tags = {
    Name        = "WordPressSNSTopic"
    Environment = "production"
    Project     = "WordPress"
  }
}

output "wordpress_alb_dns_name" {
  value = aws_alb.wordpress_alb.dns_name
}

output "wordpress_rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "wordpress_cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.wordpress_cloudfront.id
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3.bucket
}

output "wordpress_route53_zone_id" {
  value = aws_route53_zone.wordpress_route53_zone.id
}

output "wordpress_sns_topic_arn" {
  value = aws_sns_topic.wordpress_sns_topic.arn
}
