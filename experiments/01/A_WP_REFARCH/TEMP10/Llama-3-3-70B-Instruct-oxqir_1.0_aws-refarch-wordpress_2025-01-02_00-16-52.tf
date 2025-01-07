provider "aws" {
  region = "us-east-1"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "ami_id" {
  default = "ami-0c94855ba95c71c99"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "rds_instance_class" {
  default = "db.t2.small"
}

variable "efs_performance_mode" {
  default = "generalPurpose"
}

variable "cloudfront_origin_domain_name" {
  default = "" # Replace with your domain name
}

variable "route53_domain_name" {
  default = "" # Replace with your domain name
}

# Create VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

# Create subnets
resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  cidr_block        = var.public_subnet_cidrs[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  map_public_ip_on_launch = true
  availability_zone = "us-east-1a"
  tags = {
    Name = "PublicSubnet${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  cidr_block        = var.private_subnet_cidrs[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  availability_zone = "us-east-1a"
  tags = {
    Name = "PrivateSubnet${count.index + 1}"
  }
}

# Create internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Create route tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table_association" "public_route_table_association" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

resource "aws_route_table_association" "private_route_table_association" {
  count          = length(aws_subnet.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Create security groups
resource "aws_security_group" "wordpress_sg" {
  name        = "WordPressSG"
  description = "Allow inbound traffic for WordPress"
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
    Name = "WordPressSG"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "RDSSG"
  description = "Allow inbound traffic for RDS"
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
    Name = "RDSSG"
  }
}

# Create EC2 instances
resource "aws_instance" "wordpress_instance" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  subnet_id = aws_subnet.public_subnets[0].id
  key_name               = "wordpress_key"
  tags = {
    Name = "WordPressInstance"
  }
}

# Create RDS instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = var.rds_instance_class
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password123"
  parameter_group_name = "default.mysql8.0"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.wordpress_db_subnet_group.name
  skip_final_snapshot     = true
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress_db_subnet_group"
  subnet_ids = aws_subnet.private_subnets.*.id

  tags = {
    Name = "WordPressDBSubnetGroup"
  }
}

# Create Elastic Load Balancer
resource "aws_alb" "wordpress_alb" {
  name            = "WordPressALB"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_sg.id]

  tags = {
    Name = "WordPressALB"
  }
}

resource "aws_alb_target_group" "wordpress_alb_target_group" {
  name     = "WordPressALBTargetGroup"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 10
    timeout             = 5
    interval            = 10
    path                = "/"
    port                = "traffic-port"
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
}

# Create Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "WordPressASG"
  max_size            = 5
  min_size            = 1
  vpc_zone_identifier = aws_subnet.public_subnets.*.id
  target_group_arns   = [aws_alb_target_group.wordpress_alb_target_group.arn]

  launch_template {
    id      = aws_launch_template.wordpress_launch_template.id
    version = aws_launch_template.wordpress_launch_template.latest_version_number
  }
}

resource "aws_launch_template" "wordpress_launch_template" {
  name = "WordPressLaunchTemplate"

  image_id = var.ami_id

  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]

  key_name = "wordpress_key"

  tags = {
    Name = "WordPressLaunchTemplate"
  }
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cloudfront_distribution" {
  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = "WordPressALB"
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WordPressALB"

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
    Name = "WordPressCloudFrontDistribution"
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.wordpress_acm_certificate.arn
    ssl_support_method  = "sni-only"
  }
}

resource "aws_acm_certificate" "wordpress_acm_certificate" {
  domain_name       = var.cloudfront_origin_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name    = var.route53_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cloudfront_distribution.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "wordpress_route53_zone" {
  name = var.route53_domain_name
}

# Create S3 bucket
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = "wordpress-bucket"
  acl    = "private"

  versioning {
    enabled = true
  }

  tags = {
    Name = "WordPressS3Bucket"
  }
}

# Create EFS file system
resource "aws_efs_file_system" "wordpress_efs_file_system" {
  creation_token = "wordpress-efs"

  tags = {
    Name = "WordPressEFSFileSystem"
  }
}

resource "aws_efs_mount_target" "wordpress_efs_mount_target" {
  count           = length(aws_subnet.private_subnets)
  file_system_id  = aws_efs_file_system.wordpress_efs_file_system.id
  subnet_id       = aws_subnet.private_subnets[count.index].id
  security_groups = [aws_security_group.wordpress_sg.id]
}

# Create CloudWatch logs
resource "aws_cloudwatch_log_group" "wordpress_cloudwatch_log_group" {
  name = "WordPressCloudWatchLogGroup"

  retention_in_days = 30
}

resource "aws_cloudwatch_log_stream" "wordpress_cloudwatch_log_stream" {
  name           = "WordPressCloudWatchLogStream"
  log_group_name = aws_cloudwatch_log_group.wordpress_cloudwatch_log_group.name
}

# Create CloudWatch metrics
resource "aws_cloudwatch_metric_alarm" "wordpress_cloudwatch_metric_alarm" {
  alarm_name                = "WordPressCloudWatchMetricAlarm"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = 1
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = 300
  statistic                 = "Average"
  threshold                 = 80
  alarm_description         = "Alarm when CPU utilization exceeds 80%"
  insufficient_data_actions = []
  alarm_actions             = []
  ok_actions                 = []
}

output "alb_dns_name" {
  value = aws_alb.wordpress_alb.dns_name
}

output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
}

output "rds_instance_address" {
  value = aws_db_instance.wordpress_rds.address
}

output "ecs_cluster_name" {
  value = ""
}

output "ecs_service_name" {
  value = ""
}
