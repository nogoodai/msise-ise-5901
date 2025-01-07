provider "aws" {
  region = "us-west-2"
}

# VPC Configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "WordPressVPC"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Public Subnets
resource "aws_subnet" "wordpress_public_subnet_1" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name = "WordPressPublicSubnet1"
  }
}

resource "aws_subnet" "wordpress_public_subnet_2" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2b"
  tags = {
    Name = "WordPressPublicSubnet2"
  }
}

# Private Subnets
resource "aws_subnet" "wordpress_private_subnet_1" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name = "WordPressPrivateSubnet1"
  }
}

resource "aws_subnet" "wordpress_private_subnet_2" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-west-2b"
  tags = {
    Name = "WordPressPrivateSubnet2"
  }
}

# Public Route Table
resource "aws_route_table" "wordpress_public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressPublicRT"
  }
}

resource "aws_route" "wordpress_public_igw_route" {
  route_table_id         = aws_route_table.wordpress_public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Private Route Table
resource "aws_route_table" "wordpress_private_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressPrivateRT"
  }
}

# Associate Public Subnets with Public Route Table
resource "aws_route_table_association" "wordpress_public_subnet_1" {
  subnet_id      = aws_subnet.wordpress_public_subnet_1.id
  route_table_id = aws_route_table.wordpress_public_rt.id
}

resource "aws_route_table_association" "wordpress_public_subnet_2" {
  subnet_id      = aws_subnet.wordpress_public_subnet_2.id
  route_table_id = aws_route_table.wordpress_public_rt.id
}

# Associate Private Subnets with Private Route Table
resource "aws_route_table_association" "wordpress_private_subnet_1" {
  subnet_id      = aws_subnet.wordpress_private_subnet_1.id
  route_table_id = aws_route_table.wordpress_private_rt.id
}

resource "aws_route_table_association" "wordpress_private_subnet_2" {
  subnet_id      = aws_subnet.wordpress_private_subnet_2.id
  route_table_id = aws_route_table.wordpress_private_rt.id
}

# Security Groups
resource "aws_security_group" "wordpress_web_sg" {
  name        = "WordPressWebSG"
  description = "Allow HTTP/HTTPS from anywhere"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS from anywhere"
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
    Name = "WordPressWebSG"
  }
}

resource "aws_security_group" "wordpress_db_sg" {
  name        = "WordPressDBSG"
  description = "Allow MySQL from web server"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "Allow MySQL from web server"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.wordpress_web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WordPressDBSG"
  }
}

# EC2 Instances for WordPress
resource "aws_instance" "wordpress_instance_1" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.wordpress_web_sg.id]
  subnet_id = aws_subnet.wordpress_private_subnet_1.id
  key_name               = "wordpress_key"
  tags = {
    Name = "WordPressInstance1"
  }
}

resource "aws_instance" "wordpress_instance_2" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.wordpress_web_sg.id]
  subnet_id = aws_subnet.wordpress_private_subnet_2.id
  key_name               = "wordpress_key"
  tags = {
    Name = "WordPressInstance2"
  }
}

# RDS Instance for WordPress Database
resource "aws_db_instance" "wordpress_db_instance" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = "db.t2.micro"
  name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = "wordpresspassword"
  parameter_group_name = "default.mysql8.0"
  vpc_security_group_ids = [aws_security_group.wordpress_db_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  Tags = {
    Name = "WordPressDBInstance"
  }
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress_db_subnet_group"
  subnet_ids = [aws_subnet.wordpress_private_subnet_1.id, aws_subnet.wordpress_private_subnet_2.id]
  tags = {
    Name = "WordPressDBSubnetGroup"
  }
}

# Elastic Load Balancer
resource "aws_alb" "wordpress_alb" {
  name            = "wordpress-alb"
  subnets         = [aws_subnet.wordpress_public_subnet_1.id, aws_subnet.wordpress_public_subnet_2.id]
  security_groups = [aws_security_group.wordpress_web_sg.id]
  tags = {
    Name = "WordPressALB"
  }
}

resource "aws_alb_target_group" "wordpress_alb_target_group" {
  name     = "wordpress-alb-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressALBTargetGroup"
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

# Auto Scaling Group for EC2 Instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  max_size                  = 2
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity          = 1
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_launch_config.name
  vpc_zone_identifier       = [aws_subnet.wordpress_private_subnet_1.id, aws_subnet.wordpress_private_subnet_2.id]
  tags = {
    Name = "WordPressASG"
  }
}

resource "aws_launch_configuration" "wordpress_launch_config" {
  name          = "wordpress-launch-config"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.wordpress_web_sg.id]
  key_name               = "wordpress_key"
  user_data = file("${path.module}/wordpress_userdata.sh")
}

# CloudFront Distribution for Content Delivery
resource "aws_cloudfront_distribution" "wordpress_cloudfront_distribution" {
  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = "WordPressALB"
  }

  enabled         = true
  is_ipv6_enabled = true

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

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# S3 Bucket for Static Assets
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = "wordpress-static-assets"
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
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress_route53_zone" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress_alb_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_alb.wordpress_alb.dns_name
    zone_id               = aws_alb.wordpress_alb.zone_id
    evaluate_target_health = false
  }
}

output "alb_dns_name" {
  value = aws_alb.wordpress_alb.dns_name
}

output "rds_instance_endpoint" {
  value = aws_db_instance.wordpress_db_instance.endpoint
}
