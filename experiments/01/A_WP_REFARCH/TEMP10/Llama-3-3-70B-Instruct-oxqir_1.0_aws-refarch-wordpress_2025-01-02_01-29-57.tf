# Terraform configuration for WordPress on AWS

terraform {
  required_providers {
    aws = ">= 5.1.0"
  }
  required_version = ">= 1.3.5"
}

# Configure the AWS provider
provider "aws" {
  region = "us-west-2"
}

# Variables
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  default = ["us-west-2a", "us-west-2b"]
}

variable "instance_type" {
  default = "t2.micro"
}

variable "ami_id" {
  default = "ami-0c94855ba95c71c99"
}

variable "database_instance_class" {
  default = "db.t2.small"
}

variable "database_engine" {
  default = "mysql"
}

variable "efs_performance_mode" {
  default = "generalPurpose"
}

variable "cache_node_type" {
  default = "cache.t2.micro"
}

variable "cloudfront_ssl_certificate_arn" {
  default = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
}

variable "route53_zone_name" {
  default = "example.com"
}

variable "s3_bucket_name" {
  default = "example-s3-bucket"
}

# VPC and networking resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
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

resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnet_cidrs)
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "PublicSubnet${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PrivateSubnet${count.index + 1}"
  }
}

resource "aws_route_table_association" "public_route_table_association" {
  count = length(var.public_subnet_cidrs)
  subnet_id = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_route_table_association" {
  count = length(var.private_subnet_cidrs)
  subnet_id = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security groups for EC2 instances, RDS, and ELB
resource "aws_security_group" "wordpress_ec2_security_group" {
  name = "WordPressEC2SecurityGroup"
  description = "Security group for WordPress EC2 instances"
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "WordPressEC2SecurityGroup"
  }
}

resource "aws_security_group" "wordpress_rds_security_group" {
  name = "WordPressRDSSecurityGroup"
  description = "Security group for WordPress RDS instance"
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    source_security_group_id = aws_security_group.wordpress_ec2_security_group.id
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "WordPressRDSSecurityGroup"
  }
}

resource "aws_security_group" "wordpress_elb_security_group" {
  name = "WordPressELBSecurityGroup"
  description = "Security group for WordPress ELB"
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "WordPressELBSecurityGroup"
  }
}

# EC2 instances for WordPress
resource "aws_instance" "wordpress_ec2_instances" {
  count = 2
  ami = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_ec2_security_group.id]
  subnet_id = aws_subnet.public_subnets[count.index].id
  key_name = "wordpress-ec2-key"
  tags = {
    Name = "WordPressEC2Instance${count.index + 1}"
  }
}

# RDS instance for WordPress database
resource "aws_db_instance" "wordpress_rds_instance" {
  allocated_storage = 20
  engine = var.database_engine
  engine_version = "8.0.28"
  instance_class = var.database_instance_class
  name = "wordpressdb"
  username = "wordpressuser"
  password = "wordpresspassword"
  vpc_security_group_ids = [aws_security_group.wordpress_rds_security_group.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  tags = {
    Name = "WordPressRDSInstance"
  }
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name = "wordpress-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnets[0].id, aws_subnet.private_subnets[1].id]
  tags = {
    Name = "WordPressDBSubnetGroup"
  }
}

# Elastic Load Balancer
resource "aws_alb" "wordpress_elb" {
  name = "wordpress-elb"
  internal = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.wordpress_elb_security_group.id]
  subnets = [aws_subnet.public_subnets[0].id, aws_subnet.public_subnets[1].id]
  tags = {
    Name = "WordPressELB"
  }
}

resource "aws_alb_target_group" "wordpress_target_group" {
  name = "wordpress-target-group"
  port = 80
  protocol = "HTTP"
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressTargetGroup"
  }
}

resource "aws_alb_listener" "wordpress_listener" {
  load_balancer_arn = aws_alb.wordpress_elb.arn
  port = 80
  protocol = "HTTP"
  default_action {
    target_group_arn = aws_alb_target_group.wordpress_target_group.arn
    type = "forward"
  }
}

resource "aws_alb_target_group_attachment" "wordpress_target_group_attachment" {
  count = 2
  target_group_arn = aws_alb_target_group.wordpress_target_group.arn
  target_id = aws_instance.wordpress_ec2_instances[count.index].id
  port = 80
}

# Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_autoscaling_group" {
  name = "wordpress-autoscaling-group"
  max_size = 2
  min_size = 2
  vpc_zone_identifier = aws_subnet.public_subnets[0].id
  launch_configuration = aws_launch_configuration.wordpress_launch_configuration.name
  target_group_arns = [aws_alb_target_group.wordpress_target_group.arn]
  tags = {
    Name = "WordPressAutoScalingGroup"
  }
}

resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name = "wordpress-launch-configuration"
  image_id = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.wordpress_ec2_security_group.id]
  user_data = "#!/bin/bash\nsudo apt update\nsudo apt install -y apache2\nsudo ufw allow 'Apache'\nsudo service apache2 start"
}

# CloudFront distribution for content delivery
resource "aws_cloudfront_distribution" "wordpress_cloudfront_distribution" {
  origin {
    domain_name = aws_alb.wordpress_elb.dns_name
    origin_id = "wordpress-origin"
  }
  custom_origin_config {
    http_version = "http2"
    http_port = 80
    https_port = 443
    origin_protocol_policy = "match-viewer"
    origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"]
  }
  enabled = true
  web_acl_id = "null"
  default_root_object = ""
  aliases = [var.route53_zone_name]
  viewer_certificate {
    acm_certificate_arn = var.cloudfront_ssl_certificate_arn
    ssl_support_method = "sni-only"
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  tags = {
    Name = "WordPressCloudFrontDistribution"
  }
}

# S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = var.s3_bucket_name
  acl = "public-read"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "PublicReadGetObject"
        Effect = "Allow"
        Principal = "*"
        Action = "s3:GetObject"
        Resource = "arn:aws:s3:::${var.s3_bucket_name}/*"
      }
    ]
  })
  tags = {
    Name = "WordPressS3Bucket"
  }
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_route53_zone" {
  name = var.route53_zone_name
  tags = {
    Name = "WordPressRoute53Zone"
  }
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name = var.route53_zone_name
  type = "A"
  alias {
    name = aws_alb.wordpress_elb.dns_name
    zone_id = aws_alb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

# EFS configuration
resource "aws_efs_file_system" "wordpress_efs_file_system" {
  creation_token = "wordpress-efs-file-system"
  performance_mode = var.efs_performance_mode
  tags = {
    Name = "WordPressEFSFileSystem"
  }
}

resource "aws_efs_mount_target" "wordpress_efs_mount_target" {
  count = 2
  file_system_id = aws_efs_file_system.wordpress_efs_file_system.id
  subnet_id = aws_subnet.private_subnets[count.index].id
  tags = {
    Name = "WordPressEFSMountTarget${count.index + 1}"
  }
}

# Elasticache configuration
resource "aws_elasticache_cluster" "wordpress_elasticache_cluster" {
  cluster_id = "wordpress-elasticache-cluster"
  engine = "memcached"
  node_type = var.cache_node_type
  num_cache_nodes = 2
  parameter_group_name = "default.memcached1.4"
  port = 11211
  subnet_group_name = aws_elasticache_subnet_group.wordpress_elasticache_subnet_group.name
  tags = {
    Name = "WordPressElasticacheCluster"
  }
}

resource "aws_elasticache_subnet_group" "wordpress_elasticache_subnet_group" {
  name = "wordpress-elasticache-subnet-group"
  subnet_ids = [aws_subnet.private_subnets[0].id, aws_subnet.private_subnets[1].id]
  tags = {
    Name = "WordPressElasticacheSubnetGroup"
  }
}

# CloudWatch alarms
resource "aws_cloudwatch_metric_alarm" "wordpress_cpu_alarm" {
  alarm_name = "WordPressCPUAlarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = 1
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = 300
  statistic = "Average"
  threshold = 70
  actions_enabled = true
  alarm_actions = ["arn:aws:sns:us-west-2:123456789012:wordpress-sns-topic"]
}

output "wordpress_alb_dns_name" {
  value = aws_alb.wordpress_elb.dns_name
}

output "wordpress_route53_zone_name" {
  value = aws_route53_zone.wordpress_route53_zone.name
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3_bucket.id
}

output "wordpress_efs_file_system_id" {
  value = aws_efs_file_system.wordpress_efs_file_system.id
}

output "wordpress_elasticache_cluster_id" {
  value = aws_elasticache_cluster.wordpress_elasticache_cluster.id
}
