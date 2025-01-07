terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  default = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "instance_type" {
  default = "t2.micro"
}

variable "ami_id" {
  default = "ami-0c94855ba95c71c99"
}

variable "rds_instance_class" {
  default = "db.t2.small"
}

variable "rds_engine" {
  default = "mysql"
}

variable "rds_username" {
  default = "wordpress"
}

variable "rds_password" {
  sensitive = true
}

variable "s3_bucket_name" {
  default = "wordpress-static-assets"
}

variable "cloudfront_domain_name" {
  default = "wordpress.example.com"
}

variable "route53_domain_name" {
  default = "example.com"
}

variable "wordpress_version" {
  default = "latest"
}

# VPC Configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
  }
}

# Subnets
resource "aws_subnet" "public_subnets" {
  count = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PublicSubnet${count.index + 1}"
    Environment = "production"
  }
}

resource "aws_subnet" "private_subnets" {
  count = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, length(var.availability_zones) + count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PrivateSubnet${count.index + 1}"
    Environment = "production"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
  }
}

# Route Tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = "production"
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
  }
}

resource "aws_route_table_association" "public_subnets" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnets" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security Groups
resource "aws_security_group" "web_server_sg" {
  name        = "WordPressWebServerSG"
  description = "Allow inbound HTTP/HTTPS and SSH"
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
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "WordPressRDSSG"
  description = "Allow inbound MySQL"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
  }
  tags = {
    Name        = "WordPressRDSSG"
    Environment = "production"
  }
}

# EC2 Instances
resource "aws_instance" "wordpress_instances" {
  count         = length(var.availability_zones)
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.private_subnets[count.index].id
  vpc_security_group_ids = [
    aws_security_group.web_server_sg.id
  ]
  tags = {
    Name        = "WordPressInstance${count.index + 1}"
    Environment = "production"
  }
}

# RDS Instance
resource "aws_db_instance" "wordpress_rds" {
  identifier           = "wordpress-rds"
  instance_class       = var.rds_instance_class
  engine               = var.rds_engine
  engine_version       = "8.0.28"
  username             = var.rds_username
  password             = var.rds_password
  parameter_group_name = "default.mysql8.0"
  availability_zone    = var.availability_zones[0]
  db_subnet_group_name = aws_db_subnet_group.wordpress_subnet_group.name
  vpc_security_group_ids = [
    aws_security_group.rds_sg.id
  ]
  skip_final_snapshot = true
  tags = {
    Name        = "WordPressRDS"
    Environment = "production"
  }
}

resource "aws_db_subnet_group" "wordpress_subnet_group" {
  name       = "wordpress-subnet-group"
  subnet_ids = aws_subnet.private_subnets.*.id
  tags = {
    Name        = "WordPressSubnetGroup"
    Environment = "production"
  }
}

# Elastic Load Balancer
resource "aws_lb" "wordpress_elb" {
  name               = "wordpress-elb"
  internal           = false
  load_balancer_type = "application"
  subnet_mapping {
    subnet_id = aws_subnet.public_subnets[0].id
  }
  subnet_mapping {
    subnet_id = aws_subnet.public_subnets[1].id
  }
  security_groups = [
    aws_security_group.web_server_sg.id
  ]
  tags = {
    Name        = "WordPressELB"
    Environment = "production"
  }
}

resource "aws_lb_listener" "wordpress_listener" {
  load_balancer_arn = aws_lb.wordpress_elb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_target_group.arn
  }
}

resource "aws_lb_target_group" "wordpress_target_group" {
  name     = "wordpress-target-group"
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

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity          = 1
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_launch_config.name
  vpc_zone_identifier       = aws_subnet.private_subnets.*.id
  tag {
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress_launch_config" {
  name          = "wordpress-launch-config"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.web_server_sg.id
  ]
  user_data = file("${path.module}/wordpress_install.sh")
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_lb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }
  enabled = true
  default_root_object = "index.html"
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
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

# S3 Bucket
resource "aws_s3_bucket" "wordpress_static_assets" {
  bucket = var.s3_bucket_name
  acl    = "private"
  versioning {
    enabled = true
  }
  tags = {
    Name        = "WordPressStaticAssets"
    Environment = "production"
  }
}

# Route 53 Configuration
resource "aws_route53_zone" "wordpress_zone" {
  name = var.route53_domain_name
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.route53_domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cdn.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cdn.zone_id
    evaluate_target_health = false
  }
}

output "wordpress_url" {
  value = "http://${aws_route53_record.wordpress_record.name}"
}

output "wordpress_rds_instance_arn" {
  value = aws_db_instance.wordpress_rds.arn
}

output "wordpress_rds_instance_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "wordpress_elb_dns_name" {
  value = aws_lb.wordpress_elb.dns_name
}
