provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
}

variable "ec2_ami" {
  type        = string
  default     = "ami-0c55b159cbfafe1f0"
}

variable "wordpress_version" {
  type        = string
  default     = "latest"
}

variable "database_name" {
  type        = string
  default     = "wordpressdb"
}

variable "database_username" {
  type        = string
  default     = "wordpressuser"
}

variable "database_password" {
  type        = string
  sensitive   = true
}

variable "domain_name" {
  type        = string
  default     = "example.com"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name        = "WordPressVPC"
    Environment = "Production"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "Production"
  }
}

resource "aws_subnet" "wordpress_public_subnet" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name        = "WordPressPublicSubnet${count.index + 1}"
    Environment = "Production"
  }
}

resource "aws_subnet" "wordpress_private_subnet" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, length(var.availability_zones) + count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "WordPressPrivateSubnet${count.index + 1}"
    Environment = "Production"
  }
}

resource "aws_route_table" "wordpress_public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name        = "WordPressPublicRouteTable"
    Environment = "Production"
  }
}

resource "aws_route_table" "wordpress_private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressPrivateRouteTable"
    Environment = "Production"
  }
}

resource "aws_route_table_association" "wordpress_public_route_table_association" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.wordpress_public_subnet[count.index].id
  route_table_id = aws_route_table.wordpress_public_route_table.id
}

resource "aws_route_table_association" "wordpress_private_route_table_association" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.wordpress_private_subnet[count.index].id
  route_table_id = aws_route_table.wordpress_private_route_table.id
}

resource "aws_security_group" "wordpress_ec2_security_group" {
  name        = "WordPressEC2SecurityGroup"
  description = "Allow inbound traffic on port 80 and 22"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
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
    Name        = "WordPressEC2SecurityGroup"
    Environment = "Production"
  }
}

resource "aws_security_group" "wordpress_rds_security_group" {
  name        = "WordPressRDSSecurityGroup"
  description = "Allow inbound traffic on port 3306"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_ec2_security_group.id]
  }
  tags = {
    Name        = "WordPressRDSSecurityGroup"
    Environment = "Production"
  }
}

resource "aws_security_group" "wordpress_elb_security_group" {
  name        = "WordPressELBSecurityGroup"
  description = "Allow inbound traffic on port 80 and 443"
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
    Name        = "WordPressELBSecurityGroup"
    Environment = "Production"
  }
}

resource "aws_instance" "wordpress_bastion_host" {
  ami           = var.ec2_ami
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_ec2_security_group.id]
  key_name               = "wordpress-bastion-host"
  tags = {
    Name        = "WordPressBastionHost"
    Environment = "Production"
  }
}

resource "aws_efs_file_system" "wordpress_efs" {
  creation_token = "wordpress-efs"
  tags = {
    Name        = "WordPressEFS"
    Environment = "Production"
  }
}

resource "aws_efs_mount_target" "wordpress_efs_mount_target" {
  count           = length(var.availability_zones)
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = aws_subnet.wordpress_private_subnet[count.index].id
  security_groups = [aws_security_group.wordpress_ec2_security_group.id]
}

resource "aws_cloudwatch_metric_alarm" "wordpress_efs_alarm" {
  alarm_name                = "WordPressEFSSpaceAlarm"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = "2"
  metric_name               = "PercentFilesystemUsed"
  namespace                 = "AWS/EFS"
  period                    = "300"
  statistic                 = "Average"
  threshold                 = "80"
  alarm_description         = "Alarm when EFS space usage exceeds 80%"
  actions_enabled           = true
  alarm_actions             = ["arn:aws:sns:us-west-2:123456789012:wordpress-efs-alarm"]
  insufficient_data_actions = []
  ok_actions                = []
}

resource "aws_elasticache_cluster" "wordpress_elasticache" {
  cluster_id           = "wordpress-elasticache"
  engine               = "memcached"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.memcached1.4"
  port                 = 11211
  security_group_ids   = [aws_security_group.wordpress_ec2_security_group.id]
  tags = {
    Name        = "WordPressElastiCache"
    Environment = "Production"
  }
}

resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = var.rds_instance_class
  name                 = var.database_name
  username             = var.database_username
  password             = var.database_password
  vpc_security_group_ids = [aws_security_group.wordpress_rds_security_group.id]
  db_subnet_group_name    = "wordpress-rds-subnet-group"
  publicly_accessible    = false
  tags = {
    Name        = "WordPressRDS"
    Environment = "Production"
  }
}

resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = aws_subnet.wordpress_private_subnet.*.id
  tags = {
    Name        = "WordPressRDSSubnetGroup"
    Environment = "Production"
  }
}

resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.wordpress_public_subnet.*.id
  security_groups = [aws_security_group.wordpress_elb_security_group.id]
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
    Name        = "WordPressELB"
    Environment = "Production"
  }
}

resource "aws_autoscaling_group" "wordpress_autoscaling_group" {
  name                      = "wordpress-autoscaling-group"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "ELB"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_launch_configuration.name
  vpc_zone_identifier       = aws_subnet.wordpress_private_subnet.*.id
  tags = [
    {
      key                 = "Name"
      value               = "WordPressAutoScalingGroup"
      propagate_at_launch = true
    },
  ]
}

resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name          = "wordpress-launch-configuration"
  image_id      = var.ec2_ami
  instance_type = var.instance_type
  security_groups = [aws_security_group.wordpress_ec2_security_group.id]
  key_name               = "wordpress-ec2"
  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update
              sudo apt-get install -y apache2 mysql-client
              sudo a2enmod rewrite
              sudo service apache2 restart
              EOF
}

resource "aws_cloudfront_distribution" "wordpress_cloudfront" {
  origin {
    domain_name = aws_s3_bucket.wordpress_s3_bucket.bucket_regional_domain_name
    origin_id   = "wordpress-s3-origin"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [var.domain_name]
  viewer_certificate {
    acm_certificate_arn = "arn:aws:iam::123456789012:certificate/WordPressCloudFrontCertificate"
    ssl_support_method  = "sni-only"
  }
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-s3-origin"
    forwarded_values {
      query_string = false
      headers {
        quantity = 0
      }
      cookies {
        forward = "none"
      }
    }
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "allow-all"
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  tags = {
    Name        = "WordPressCloudFront"
    Environment = "Production"
  }
}

resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket        = var.domain_name
  acl           = "private"
  force_destroy = true
  policy        = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource = "arn:aws:s3:::${var.domain_name}/*"
      },
    ]
  })
  tags = {
    Name        = "WordPressS3Bucket"
    Environment = "Production"
  }
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cloudfront.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cloudfront.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "wordpress_route53_zone" {
  name = var.domain_name
}

resource "aws_cloudwatch_log_group" "wordpress_cloudwatch_log_group" {
  name = "wordpress-cloudwatch-log-group"
}

resource "aws_cloudwatch_log_stream" "wordpress_cloudwatch_log_stream" {
  name           = "wordpress-cloudwatch-log-stream"
  log_group_name = aws_cloudwatch_log_group.wordpress_cloudwatch_log_group.name
}

resource "aws_cloudwatch_metric_alarm" "wordpress_cpu_alarm" {
  alarm_name                = "WordPressCPUAlarm"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = "2"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "300"
  statistic                 = "Average"
  threshold                 = "80"
  alarm_description         = "Alarm when CPU utilization exceeds 80%"
  actions_enabled           = true
  alarm_actions             = ["arn:aws:sns:us-west-2:123456789012:wordpress-cpu-alarm"]
  insufficient_data_actions = []
  ok_actions                = []
}

output "wordpress_vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "wordpress_cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.wordpress_cloudfront.id
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3_bucket.id
}

output "wordpress_route53_zone_id" {
  value = aws_route53_zone.wordpress_route53_zone.id
}
