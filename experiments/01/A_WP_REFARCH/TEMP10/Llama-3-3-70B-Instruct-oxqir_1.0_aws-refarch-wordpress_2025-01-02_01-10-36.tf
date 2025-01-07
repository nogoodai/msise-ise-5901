# Specify the provider and version
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Configure the AWS provider
provider "aws" {
  region = "us-east-1"
}

# Define variables
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "ami_id" {
  default = "ami-0c94855ba95c71c99"
}

variable "wordpress_db_name" {
  default = "wordpress"
}

variable "wordpress_db_username" {
  default = "wordpress"
}

variable "wordpress_db_password" {
  default = "wordpress"
}

# Create VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

# Create subnets
resource "aws_subnet" "public_subnet_1" {
  cidr_block = "10.0.1.0/24"
  vpc_id     = aws_vpc.wordpress_vpc.id
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "Public Subnet 1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  cidr_block = "10.0.2.0/24"
  vpc_id     = aws_vpc.wordpress_vpc.id
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "Public Subnet 2"
  }
}

resource "aws_subnet" "private_subnet_1" {
  cidr_block = "10.0.3.0/24"
  vpc_id     = aws_vpc.wordpress_vpc.id
  availability_zone = "us-east-1a"
  tags = {
    Name = "Private Subnet 1"
  }
}

resource "aws_subnet" "private_subnet_2" {
  cidr_block = "10.0.4.0/24"
  vpc_id     = aws_vpc.wordpress_vpc.id
  availability_zone = "us-east-1b"
  tags = {
    Name = "Private Subnet 2"
  }
}

# Create internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPress Internet Gateway"
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
    Name = "Public Route Table"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "Private Route Table"
  }
}

# Associate subnets with route tables
resource "aws_route_table_association" "public_subnet_1_assoc" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_2_assoc" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnet_1_assoc" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_subnet_2_assoc" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_route_table.id
}

# Create security groups
resource "aws_security_group" "wordpress_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  name        = "WordPress Security Group"
  description = "Allow inbound traffic on port 80 and 443"
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
    Name = "WordPress Security Group"
  }
}

resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  name        = "RDS Security Group"
  description = "Allow inbound traffic on port 3306"
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
    Name = "RDS Security Group"
  }
}

# Create EC2 instances
resource "aws_instance" "wordpress_instance_1" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  subnet_id = aws_subnet.public_subnet_1.id
  key_name               = "wordpress"
  user_data = <<-EOF
              #!/bin/bash
              echo "Installing WordPress"
              EOF
  tags = {
    Name = "WordPress Instance 1"
  }
}

resource "aws_instance" "wordpress_instance_2" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  subnet_id = aws_subnet.public_subnet_2.id
  key_name               = "wordpress"
  user_data = <<-EOF
              #!/bin/bash
              echo "Installing WordPress"
              EOF
  tags = {
    Name = "WordPress Instance 2"
  }
}

# Create RDS instance
resource "aws_db_instance" "wordpress_rds" {
  identifier = "wordpress-rds"
  instance_class = "db.t2.micro"
  engine = "mysql"
  engine_version = "8.0.23"
  multi_az = true
  username = var.wordpress_db_username
  password = var.wordpress_db_password
  db_name = var.wordpress_db_name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  storage_type = "gp2"
  allocated_storage = 20
  tags = {
    Name = "WordPress RDS"
  }
}

# Create Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  security_groups = [aws_security_group.wordpress_sg.id]
  instances       = [aws_instance.wordpress_instance_1.id, aws_instance.wordpress_instance_2.id]
  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port          = 80
    lb_protocol      = "http"
  }
  tags = {
    Name = "WordPress ELB"
  }
}

# Create Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "wordpress-asg"
  min_size            = 2
  max_size            = 4
  health_check_type   = "ELB"
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  target_group_arns = [aws_lb_target_group.wordpress_tg.arn]
  tags = {
    Name = "WordPress ASG"
  }
}

resource "aws_launch_configuration" "wordpress_lc" {
  name            = "wordpress-lc"
  image_id        = var.ami_id
  instance_type   = var.instance_type
  security_groups = [aws_security_group.wordpress_sg.id]
  key_name        = "wordpress"
  user_data = <<-EOF
              #!/bin/bash
              echo "Installing WordPress"
              EOF
  lifecycle {
    create_before_destroy = true
  }
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_lb.wordpress_elb.dns_name
    origin_id   = "wordpressOrigin"
  }
  enabled = true
  default_root_object = "index.html"
  aliases = ["example.com", "www.example.com"]
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpressOrigin"
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
  viewer_certificate {
    acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "sni-only"
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  tags = {
    Name = "WordPress CloudFront Distribution"
  }
}

# Create S3 bucket
resource "aws_s3_bucket" "wordpress_s3" {
  bucket = "example-wordpress-bucket"
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
  tags = {
    Name = "WordPress S3 Bucket"
  }
}

# Create Route 53 hosted zone
resource "aws_route53_zone" "wordpress_route53" {
  name = "example.com"
  tags = {
    Name = "WordPress Route 53 Zone"
  }
}

# Create Route 53 records
resource "aws_route53_record" "wordpress_a_record" {
  zone_id = aws_route53_zone.wordpress_route53.id
  name    = "example.com"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cfd.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cfd.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "wordpress_cname_record" {
  zone_id = aws_route53_zone.wordpress_route53.id
  name    = "www.example.com"
  type    = "CNAME"
  records = [aws_cloudfront_distribution.wordpress_cfd.domain_name]
  ttl     = 60
}

# Create CloudWatch alarm for CPU utilization
resource "aws_cloudwatch_metric_alarm" "cpu_utilization_alarm" {
  alarm_name          = "cpu-utilization-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_actions       = [aws_sns_topic.wordpress_sns_topic.arn]
  insufficient_data_actions = []
  ok_actions          = []
}

# Create CloudWatch log group
resource "aws_cloudwatch_log_group" "wordpress_log_group" {
  name = "wordpress-log-group"
  retention_in_days = 30
  tags = {
    Name = "WordPress CloudWatch Log Group"
  }
}

# Create CloudWatch log stream
resource "aws_cloudwatch_log_stream" "wordpress_log_stream" {
  name           = "wordpress-log-stream"
  log_group_name = aws_cloudwatch_log_group.wordpress_log_group.name
  tags = {
    Name = "WordPress CloudWatch Log Stream"
  }
}

output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "rds_instance_arn" {
  value = aws_db_instance.wordpress_rds.arn
}

output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cfd.domain_name
}
