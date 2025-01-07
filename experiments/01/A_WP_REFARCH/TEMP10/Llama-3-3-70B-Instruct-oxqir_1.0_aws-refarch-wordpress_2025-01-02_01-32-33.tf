# Specify the provider and version for Terraform
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.1.0"
    }
  }
  required_version = ">= 1.4.5"
}

# Configure the AWS provider with default region
provider "aws" {
  region = "us-west-2"
}

# VPC configuration
variable "vpc_cidr_block" {
  default = "10.0.0.0/16"
}
variable "vpc_name" {
  default = "WordPressVPC"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name = var.vpc_name
  }
}

# Subnet configuration
variable "public_subnet_cidr_blocks" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}
variable "private_subnet_cidr_blocks" {
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}
variable "availability_zones" {
  default = ["us-west-2a", "us-west-2b"]
}

resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnet_cidr_blocks)
  cidr_block = var.public_subnet_cidr_blocks[count.index]
  vpc_id     = aws_vpc.wordpress_vpc.id
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = "true"
  tags = {
    Name = "PublicSubnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnet_cidr_blocks)
  cidr_block = var.private_subnet_cidr_blocks[count.index]
  vpc_id     = aws_vpc.wordpress_vpc.id
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PrivateSubnet-${count.index + 1}"
  }
}

# Internet Gateway configuration
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Route Table configuration
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
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

# Route configuration
resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Association of subnets to route tables
resource "aws_route_table_association" "public_subnets" {
  count = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnets" {
  count = length(aws_subnet.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security Groups configuration
variable "ssh_ingress_cidrs" {
  default = ["0.0.0.0/0"]
}

resource "aws_security_group" "web_server_sg" {
  name        = "WebServerSG"
  description = "Security group for web servers"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = var.ssh_ingress_cidrs
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

resource "aws_security_group" "rds_sg" {
  name        = "RDSSG"
  description = "Security group for RDS"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
  }
  tags = {
    Name = "RDSSG"
  }
}

# EC2 configuration
variable "instance_type" {
  default = "t2.micro"
}
variable "ami_id" {
  default = "ami-0c94855ba95c71c99"
}

resource "aws_instance" "wordpress" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  subnet_id = aws_subnet.public_subnets[0].id
  tags = {
    Name = "WordPressInstance"
  }
}

# RDS configuration
variable "rds_instance_class" {
  default = "db.t2.micro"
}

resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 10
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = var.rds_instance_class
  name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = "wordpresspassword"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_subnet_group.name
  skip_final_snapshot  = true
}

resource "aws_db_subnet_group" "wordpress_subnet_group" {
  name       = "wordpress_subnet_group"
  subnet_ids = aws_subnet.private_subnets[*].id
}

# Elastic Load Balancer configuration
resource "aws_alb" "wordpress_alb" {
  name            = "WordPressALB"
  subnets         = aws_subnet.public_subnets[*].id
  security_groups = [aws_security_group.web_server_sg.id]
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

resource "aws_alb_target_group" "wordpress_alb_target_group" {
  name     = "WordPressALBTargetGroup"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
}

resource "aws_alb_target_group_attachment" "wordpress_alb_target_group_attachment" {
  target_group_arn = aws_alb_target_group.wordpress_alb_target_group.arn
  target_id        = aws_instance.wordpress.id
  port             = 80
}

# Auto Scaling Group configuration
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  max_size                  = 3
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete         = true
  launch_configuration = aws_launch_configuration.wordpress_launch_config.name
  vpc_zone_identifier  = aws_subnet.public_subnets[*].id
}

resource "aws_launch_configuration" "wordpress_launch_config" {
  name          = "WordPressLaunchConfig"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_server_sg.id]
}

# CloudFront distribution configuration
resource "aws_cloudfront_distribution" "wordpress_cloudfront" {
  enabled = true
  aliases = ["example.com", "www.example.com"]

  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = "wordpress-alb"
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "match-viewer"
      origin_ssl_protocols      = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }

  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-alb"

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

# S3 bucket configuration
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = "example-bucket"
  acl    = "private"

  tags = {
    Name = "WordPressS3Bucket"
  }
}

# Route 53 configuration
resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_alb.wordpress_alb.dns_name
    zone_id               = aws_alb.wordpress_alb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "wordpress_route53_zone" {
  name = "example.com"
}

output "rds_instance_arn" {
  value = aws_db_instance.wordpress_rds.arn
}
output "alb_dns_name" {
  value = aws_alb.wordpress_alb.dns_name
}
output "s3_bucket_arn" {
  value = aws_s3_bucket.wordpress_s3_bucket.arn
}
output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.wordpress_cloudfront.id
}
output "ec2_instance_id" {
  value = aws_instance.wordpress.id
}
output "route53_zone_id" {
  value = aws_route53_zone.wordpress_route53_zone.id
}
output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}
