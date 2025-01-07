terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Variables
variable "region" {
  type    = string
  default = "us-west-2"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-west-2a", "us-west-2b"]
}

variable "database_username" {
  type    = string
  default = "admin"
}

variable "database_password" {
  type    = string
  sensitive = true
}

variable "domain_name" {
  type    = string
  default = "example.com"
}

variable "ssh_cidr_blocks" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "ami_id" {
  type    = string
  default = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 AMI ID
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

variable "efs_performance_mode" {
  type    = string
  default = "generalPurpose"
}

variable "elasticache_engine" {
  type    = string
  default = "redis"
}

variable "elasticache_node_type" {
  type    = string
  default = "cache.t2.micro"
}

variable "elasticache_num_cache_nodes" {
  type    = number
  default = 1
}

variable "rds_engine" {
  type    = string
  default = "mysql"
}

variable "rds_instance_class" {
  type    = string
  default = "db.t2.micro"
}

# Provider
provider "aws" {
  region = var.region
}

# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "WordPress-Internet-Gateway"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "WordPress-Public-Subnet-${count.index + 1}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "WordPress-Private-Subnet-${count.index + 1}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name        = "WordPress-Public-Route-Table"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "WordPress-Private-Route-Table"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security Groups
resource "aws_security_group" "web_server" {
  name        = "WordPress-Web-Server-SG"
  description = "Allow HTTP, HTTPS, and SSH traffic"
  vpc_id      = aws_vpc.main.id

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
    cidr_blocks = var.ssh_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WordPress-Web-Server-SG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "database" {
  name        = "WordPress-Database-SG"
  description = "Allow traffic from web server to database"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server.id]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.web_server.id]
  }

  tags = {
    Name        = "WordPress-Database-SG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "elb" {
  name        = "WordPress-ELB-SG"
  description = "Allow HTTP and HTTPS traffic to ELB"
  vpc_id      = aws_vpc.main.id

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
    Name        = "WordPress-ELB-SG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# EC2 Instances for WordPress
resource "aws_instance" "wordpress" {
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.web_server.id]
  key_name      = "WordPress-Key"

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y httpd php php-mysqlnd
              sudo systemctl start httpd
              sudo systemctl enable httpd
              sudo mkdir -p /var/www/html/wordpress
              sudo chown -R ec2-user:ec2-user /var/www/html/wordpress
              wget https://wordpress.org/latest.tar.gz
              tar -xzf latest.tar.gz -C /var/www/html/wordpress --strip-components=1
              sudo chown -R apache:apache /var/www/html/wordpress
              EOF

  tags = {
    Name        = "WordPress-Instance"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# RDS Instance for WordPress Database
resource "aws_db_instance" "wordpress" {
  identifier             = "wordpress-db"
  engine                 = var.rds_engine
  engine_version         = "5.7"
  instance_class         = var.rds_instance_class
  allocated_storage      = 20
  storage_type           = "gp2"
  db_name                = "wordpress"
  username               = var.database_username
  password               = var.database_password
  vpc_security_group_ids = [aws_security_group.database.id]
  multi_az               = true
  publicly_accessible    = false
  skip_final_snapshot    = true

  tags = {
    Name        = "WordPress-Database"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Elastic Load Balancer
resource "aws_lb" "wordpress" {
  name               = "wordpress-elb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.elb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name        = "WordPress-ELB"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}

resource "aws_lb_target_group" "wordpress" {
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    healthy_threshold   = 3
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
  }

  tags = {
    Name        = "WordPress-Target-Group"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Auto Scaling Group for EC2 Instances
resource "aws_launch_template" "wordpress" {
  name_prefix   = "wordpress-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  user_data     = base64encode(aws_instance.wordpress.user_data)

  vpc_security_group_ids = [aws_security_group.web_server.id]

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "WordPress-Instance"
      Environment = "Production"
      Project     = "WordPress"
    }
  }
}

resource "aws_autoscaling_group" "wordpress" {
  name                = "wordpress-asg"
  vpc_zone_identifier = aws_subnet.public[*].id
  target_group_arns   = [aws_lb_target_group.wordpress.arn]

  launch_template {
    id      = aws_launch_template.wordpress.id
    version = "$Latest"
  }

  min_size             = 1
  max_size             = 3
  desired_capacity     = 1
  health_check_type    = "ELB"
  force_delete         = true

  tag {
    key                 = "Name"
    value               = "WordPress-Instance"
    propagate_at_launch = true
  }
}

# CloudFront Distribution for Content Delivery
resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_lb.wordpress.dns_name
    origin_id   = "WordPress-Origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.php"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WordPress-Origin"

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
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

  tags = {
    Name        = "WordPress-CloudFront"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# S3 Bucket for Static Assets
resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${var.domain_name}"
  acl    = "private"

  tags = {
    Name        = "WordPress-Assets-Bucket"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket_public_access_block" "wordpress_assets" {
  bucket = aws_s3_bucket.wordpress_assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress" {
  name = var.domain_name

  tags = {
    Name        = "WordPress-DNS-Zone"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route53_record" "elb" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = "elb.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.wordpress.dns_name
    zone_id                = aws_lb.wordpress.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "cloudfront" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress.hosted_zone_id
    evaluate_target_health = false
  }
}

# Monitoring and Dashboards
resource "aws_cloudwatch_dashboard" "wordpress" {
  dashboard_name = "WordPress-Performance-Dashboard"

  dashboard_body = <<EOF
{
  "widgets": [
    {
      "type": "metric",
      "x": 0,
      "y": 0,
      "width": 6,
      "height": 6,
      "properties": {
        "metrics": [
          [
            "AWS/RDS",
            "CPUUtilization",
            "DBInstanceIdentifier",
            "${aws_db_instance.wordpress.identifier}"
          ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${var.region}",
        "title": "RDS CPU Utilization"
      }
    },
    {
      "type": "metric",
      "x": 6,
      "y": 0,
      "width": 6,
      "height": 6,
      "properties": {
        "metrics": [
          [
            "AWS/EC2",
            "CPUUtilization",
            "InstanceId",
            "${aws_instance.wordpress.id}"
          ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${var.region}",
        "title": "EC2 CPU Utilization"
      }
    }
  ]
}
EOF
}

# Outputs
output "elb_dns_name" {
  value = aws_lb.wordpress.dns_name
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress.domain_name
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress.endpoint
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_assets.bucket
}

output "route53_zone_id" {
  value = aws_route53_zone.wordpress.zone_id
}
