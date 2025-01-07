provider "aws" {
  region = "us-west-2"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
}

variable "rds_engine" {
  type        = string
  default     = "mysql"
}

variable "rds_username" {
  type        = string
  default     = "wordpress"
}

variable "rds_password" {
  type        = string
  sensitive   = true
}

variable "efs_performance_mode" {
  type        = string
  default     = "generalPurpose"
}

variable "elasticache_node_type" {
  type        = string
  default     = "cache.t2.micro"
}

variable "elasticache_engine" {
  type        = string
  default     = "memcached"
}

variable "cloudfront_ssl_certificate" {
  type        = string
  default     = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
}

variable "route53_domain_name" {
  type        = string
  default     = "example.com"
}

# VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
    Project     = "WordPress"
  }
}

# Subnets
resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnets)

  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PublicSubnet${count.index + 1}"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnets)

  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PrivateSubnet${count.index + 1}"
    Environment = "production"
    Project     = "WordPress"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
    Project     = "WordPress"
  }
}

# Route Tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = "production"
    Project     = "WordPress"
  }
}

# Security Groups
resource "aws_security_group" "web_server_sg" {
  name        = "WordPressWebServerSG"
  description = "Security group for WordPress web servers"
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
    Name        = "WordPressWebServerSG"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "WordPressRDSSG"
  description = "Security group for WordPress RDS instance"
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

  tags = {
    Name        = "WordPressRDSSG"
    Environment = "production"
    Project     = "WordPress"
  }
}

# EC2 Instances
resource "aws_instance" "wordpress_instance" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.web_server_sg.id
  ]
  subnet_id = aws_subnet.public_subnets[0].id
  tags = {
    Name        = "WordPressInstance"
    Environment = "production"
    Project     = "WordPress"
  }
}

# RDS Instance
resource "aws_db_instance" "wordpress_rds_instance" {
  allocated_storage    = 20
  engine               = var.rds_engine
  engine_version       = "5.7"
  instance_class       = var.rds_instance_class
  name                 = "wordpressdb"
  username             = var.rds_username
  password             = var.rds_password
  vpc_security_group_ids = [
    aws_security_group.rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  tags = {
    Name        = "WordPressRDSInstance"
    Environment = "production"
    Project     = "WordPress"
  }
}

# DB Subnet Group
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpressdbsubnetgroup"
  subnet_ids = aws_subnet.private_subnets.*.id

  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = "production"
    Project     = "WordPress"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpresselb"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.web_server_sg.id]

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
    ssl_certificate_id = var.cloudfront_ssl_certificate
  }

  tags = {
    Name        = "WordPressELB"
    Environment = "production"
    Project     = "WordPress"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "wordpressasg"
  max_size            = 5
  min_size            = 1
  vpc_zone_identifier = aws_subnet.public_subnets[0].id

  launch_template {
    id      = aws_launch_template.wordpress_launch_template.id
    version = "$Latest"
  }

  tags = [
    {
      key                 = "Name"
      value               = "WordPressASG"
      propagate_at_launch = true
    },
  ]
}

# Launch Template
resource "aws_launch_template" "wordpress_launch_template" {
  name          = "wordpresslaunchtemplate"
  image_id      = var.ami_id
  instance_type = var.instance_type

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web_server_sg.id]
  }

  tags = {
    Name        = "WordPressLaunchTemplate"
    Environment = "production"
    Project     = "WordPress"
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cloudfront_distribution" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

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
    acm_certificate_arn = var.cloudfront_ssl_certificate
    ssl_support_method   = "sni-only"
  }

  tags = {
    Name        = "WordPressCloudFrontDistribution"
    Environment = "production"
    Project     = "WordPress"
  }
}

# S3 Bucket
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = "wordpress-s3-bucket"
  acl    = "private"

  versioning {
    enabled = true
  }

  tags = {
    Name        = "WordPressS3Bucket"
    Environment = "production"
    Project     = "WordPress"
  }
}

# Route 53 DNS Configuration
resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.zone_id
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

# EFS Configuration
resource "aws_efs_file_system" "wordpress_efs_file_system" {
  creation_token = "wordpress-efs-file-system"

  tags = {
    Name        = "WordPressEFSFileSystem"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_efs_mount_target" "wordpress_efs_mount_target" {
  file_system_id = aws_efs_file_system.wordpress_efs_file_system.id
  subnet_id       = aws_subnet.private_subnets[0].id
}

# Elasticache Configuration
resource "aws_elasticache_cluster" "wordpress_elasticache_cluster" {
  cluster_id           = "wordpress-elasticache-cluster"
  engine               = var.elasticache_engine
  node_type            = var.elasticache_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.memcached1.4"
  port                 = 11211

  tags = {
    Name        = "WordPressElasticacheCluster"
    Environment = "production"
    Project     = "WordPress"
  }
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "wordpress_cloudwatch_alarm" {
  alarm_name          = "WordPressCloudWatchAlarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Trigger an alarm when CPU utilization is greater than or equal to 70%"

  actions_enabled = true
  alarm_actions   = [aws_sns_topic.wordpress_sns_topic.arn]

  tags = {
    Name        = "WordPressCloudWatchAlarm"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_sns_topic" "wordpress_sns_topic" {
  name = "wordpress-sns-topic"

  tags = {
    Name        = "WordPressSNSTopic"
    Environment = "production"
    Project     = "WordPress"
  }
}

# Output
output "wordpress_cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
}

output "wordpress_rds_instance_endpoint" {
  value = aws_db_instance.wordpress_rds_instance.endpoint
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3_bucket.id
}

output "wordpress_route53_record_name" {
  value = aws_route53_record.wordpress_route53_record.name
}

output "wordpress_efs_file_system_id" {
  value = aws_efs_file_system.wordpress_efs_file_system.id
}

output "wordpress_elasticache_cluster_id" {
  value = aws_elasticache_cluster.wordpress_elasticache_cluster.id
}
