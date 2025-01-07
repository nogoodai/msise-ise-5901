# Configure the AWS provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Define AWS provider and region
provider "aws" {
  region = "us-west-2"
}

# Define variables
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}
variable "public_subnet_cidr" {
  default = "10.0.1.0/24"
}
variable "private_subnet_cidr" {
  default = "10.0.2.0/24"
}
variable "bastion_ami" {
  default = "ami-0c94855ba95c71c99"
}
variable "instance_type" {
  default = "t2.micro"
}
variable "database_instance_class" {
  default = "db.t2.small"
}
variable "rds_engine" {
  default = "mysql"
}
variable "elasticache_node_type" {
  default = "cache.t2.micro"
}
variable "elasticache_num_nodes" {
  default = 1
}
variable "cloudfront_s3_bucket" {
  default = "my-bucket"
}
variable "route53_domain_name" {
  default = "example.com"
}

# Create VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

# Create public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidr
  availability_zone = "us-west-2a"
}

# Create private subnet
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = "us-west-2a"
}

# Create internet gateway
resource "aws_internet_gateway" "wordpress_gateway" {
  vpc_id = aws_vpc.wordpress_vpc.id
}

# Create public route table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_gateway.id
  }
  tags = {
    Name = "PublicRouteTable"
  }
}

# Create private route table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

# Create security groups
resource "aws_security_group" "web_server_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
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
    Name = "WebServerSG"
  }
}

resource "aws_security_group" "database_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
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
    Name = "DatabaseSG"
  }
}

# Create EC2 instance for bastion host
resource "aws_instance" "bastion_host" {
  ami           = var.bastion_ami
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.web_server_sg.id
  ]
  subnet_id = aws_subnet.public_subnet.id
  key_name               = "my-key-pair"
  tags = {
    Name = "BastionHost"
  }
}

# Create EFS file system
resource "aws_efs_file_system" "wordpress_efs" {
  creation_token = "wordpress-efs"

  tags = {
    Name = "WordPressEFS"
  }
}

# Create EFS mount target
resource "aws_efs_mount_target" "wordpress_mount_target" {
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id       = aws_subnet.private_subnet.id
}

# Create CloudWatch alarms for EFS
resource "aws_cloudwatch_metric_alarm" "efs_throughput_alarm" {
  alarm_name          = "EFS-Throughput-Alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Throughput"
  namespace           = "AWS/EFS"
  period              = "300"
  statistic           = "Average"
  threshold           = "100"
  alarm_description   = "EFS throughput is high"
}

resource "aws_cloudwatch_metric_alarm" "efs_burst_credit_alarm" {
  alarm_name          = "EFS-Burst-Credit-Alarm"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = "300"
  statistic           = "Average"
  threshold           = "100"
  alarm_description   = "EFS burst credit balance is low"
}

# Create Elasticache cluster
resource "aws_elasticache_cluster" "wordpress_elasticache" {
  cluster_id           = "wordpress-elasticache"
  engine               = "memcached"
  node_type            = var.elasticache_node_type
  num_cache_nodes      = var.elasticache_num_nodes
  parameter_group_name = "default.memcached1.6"
  port                 = 11211
  subnet_group_name    = "wordpress-subnet-group"
  security_group_ids = [
    aws_security_group.database_sg.id
  ]
  tags = {
    Name = "WordPressElasticache"
  }
}

# Create RDS instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = var.rds_engine
  engine_version       = "8.0.28"
  instance_class       = var.database_instance_class
  db_name              = "wordpress"
  username             = "wordpress_user"
  password             = "wordpress_password"
  vpc_security_group_ids = [
    aws_security_group.database_sg.id
  ]
  db_subnet_group_name = "wordpress-subnet-group"
  multi_az             = true
  tags = {
    Name = "WordPressRDS"
  }
}

# Create Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = [aws_subnet.public_subnet.id]
  security_groups = [aws_security_group.web_server_sg.id]
  listener {
    lb_port       = 80
    lb_protocol   = "http"
    instance_port = 80
    instance_protocol = "http"
  }
  tags = {
    Name = "WordPressELB"
  }
}

# Create Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  launch_configuration      = aws_launch_configuration.wordpress_launch_config.name
  min_size                  = 1
  max_size                  = 3
  vpc_zone_identifier       = [aws_subnet.private_subnet.id]
  health_check_grace_period = 300
  health_check_type         = "ELB"
  force_delete              = true
  tags = [
    {
      key                 = "Name"
      value               = "WordPressASG"
      propagate_at_launch = true
    },
  ]
}

# Create Launch Configuration for EC2 instances
resource "aws_launch_configuration" "wordpress_launch_config" {
  name          = "wordpress-launch-config"
  image_id      = var.bastion_ami
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.web_server_sg.id
  ]
  user_data = <<EOF
#!/bin/bash
sudo apt-get update -y
sudo apt-get install -y apache2 php7.2 mysql-client
sudo service apache2 start
EOF
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_s3_bucket.wordpress_bucket.bucket_regional_domain_name
    origin_id   = "S3Origin"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [var.route53_domain_name]
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.wordpress_cert.arn
    ssl_support_method  = "sni-only"
  }
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/404.html"
  }
  tags = {
    Name = "WordPressDistribution"
  }
}

# Create S3 bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = var.cloudfront_s3_bucket
  acl    = "private"
  tags = {
    Name = "WordPressBucket"
  }
}

# Create Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_zone" {
  name = var.route53_domain_name
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.route53_domain_name
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

# Create CloudWatch dashboard
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
        "metric": "AWS/EFS/Throughput",
        "region": "us-west-2",
        "stat": "Average",
        "period": 300,
        "title": "EFS Throughput"
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
        "region": "us-west-2",
        "stat": "Average",
        "period": 300,
        "title": "RDS Database Connections"
      }
    }
  ]
}
EOF
}

# Create IAM role and policy for EC2 instances
resource "aws_iam_role" "wordpress_iam_role" {
  name        = "wordpress-iam-role"
  description = "IAM role for WordPress EC2 instances"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "wordpress_iam_policy" {
  name        = "wordpress-iam-policy"
  description = "IAM policy for WordPress EC2 instances"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${var.cloudfront_s3_bucket}",
        "arn:aws:s3:::${var.cloudfront_s3_bucket}/*"
      ],
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "wordpress_iam_policy_attachment" {
  role       = aws_iam_role.wordpress_iam_role.name
  policy_arn = aws_iam_policy.wordpress_iam_policy.arn
}

# Create ACM certificate for CloudFront
resource "aws_acm_certificate" "wordpress_cert" {
  domain_name       = var.route53_domain_name
  validation_method = "DNS"
}

resource "aws_route53_record" "wordpress_cert_validation" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = aws_acm_certificate.wordpress_cert.domain_validation_options[0].resource_record_name
  type    = aws_acm_certificate.wordpress_cert.domain_validation_options[0].resource_record_type
  records = [aws_acm_certificate.wordpress_cert.domain_validation_options[0].resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "wordpress_cert_validation" {
  certificate_arn = aws_acm_certificate.wordpress_cert.arn
  validation_record {
    name    = aws_acm_certificate.wordpress_cert.domain_validation_options[0].resource_record_name
    type    = aws_acm_certificate.wordpress_cert.domain_validation_options[0].resource_record_type
    value   = aws_acm_certificate.wordpress_cert.domain_validation_options[0].resource_record_value
  }
}

output "wordpress_vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_rds_instance_address" {
  value = aws_db_instance.wordpress_rds.address
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_bucket.bucket
}

output "wordpress_route53_zone_id" {
  value = aws_route53_zone.wordpress_zone.id
}

output "wordpress_cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.wordpress_distribution.id
}

output "wordpress_cloudwatch_dashboard_id" {
  value = aws_cloudwatch_dashboard.wordpress_dashboard.dashboard_id
}
