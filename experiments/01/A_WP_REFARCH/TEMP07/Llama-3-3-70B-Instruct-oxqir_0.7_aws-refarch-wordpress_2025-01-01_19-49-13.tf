provider "aws" {
  region = "us-west-2"
}

# VPC Configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "WordPressVPC"
  }
}

# Subnets
resource "aws_subnet" "public_subnet_1" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name = "PublicSubnet1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2b"
  tags = {
    Name = "PublicSubnet2"
  }
}

resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name = "PrivateSubnet1"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-west-2b"
  tags = {
    Name = "PrivateSubnet2"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Route Tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicRouteTable"
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
    Name = "PrivateRouteTable"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public_subnet_1_association" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_2_association" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnet_1_association" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_subnet_2_association" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_route_table.id
}

# Security Groups
resource "aws_security_group" "web_server_sg" {
  name        = "WebServerSG"
  description = "Allow HTTP, HTTPS, and SSH traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "Allow HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow SSH traffic"
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

resource "aws_security_group" "rds_sg" {
  name        = "RDSSG"
  description = "Allow MySQL traffic from web server"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "Allow MySQL traffic"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
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

resource "aws_security_group" "elb_sg" {
  name        = "ELBSG"
  description = "Allow HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "Allow HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS traffic"
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
    Name = "ELBSG"
  }
}

# EC2 Instances
resource "aws_instance" "wordpress_instance" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  subnet_id = aws_subnet.private_subnet_1.id
  key_name               = "wordpress-key"
  tags = {
    Name = "WordPressInstance"
  }
}

# RDS Instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = "db.t2.micro"
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password123"
  parameter_group_name = "default.mysql8.0"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  skip_final_snapshot  = true
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
}

# Elastic Load Balancer
resource "aws_alb" "wordpress_alb" {
  name            = "WordPressALB"
  subnets         = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  security_groups = [aws_security_group.elb_sg.id]
}

resource "aws_alb_target_group" "wordpress_alb_target_group" {
  name     = "WordPressALBTargetGroup"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
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

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "WordPressASG"
  max_size            = 5
  min_size            = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity          = 1
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_launch_config.name
  vpc_zone_identifier       = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
}

resource "aws_launch_configuration" "wordpress_launch_config" {
  name          = "WordPressLaunchConfig"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.web_server_sg.id]
  key_name               = "wordpress-key"
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = "WordPressALB"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

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
    acm_certificate_arn = aws_acm_certificate.wordpress_acm.arn
    ssl_support_method  = "sni-only"
  }
}

resource "aws_acm_certificate" "wordpress_acm" {
  domain_name       = "example.com"
  validation_method = "DNS"
}

# S3 Bucket
resource "aws_s3_bucket" "wordpress_s3" {
  bucket = "wordpress-s3-bucket"
  acl    = "private"

  tags = {
    Name        = "WordPressS3Bucket"
    Environment = "Dev"
  }
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress_route53" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53.id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_alb.wordpress_alb.dns_name
    zone_id               = aws_alb.wordpress_alb.zone_id
    evaluate_target_health = false
  }
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "wordpress_cw_alarm" {
  alarm_name                = "WordPressCWAlarm"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = "2"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "300"
  statistic                  = "Average"
  threshold                 = "80"
  alarm_description         = "This metric alarm monitors the CPU utilization of the WordPress instance"
  actions_enabled           = true
  alarm_actions             = [aws_sns_topic.wordpress_sns_topic.arn]
}

resource "aws_sns_topic" "wordpress_sns_topic" {
  name = "WordPressSNSTopic"
}

resource "aws_sns_topic_subscription" "wordpress_sns_subscription" {
  topic_arn = aws_sns_topic.wordpress_sns_topic.arn
  protocol  = "email"
  endpoint  = "example@example.com"
}

output "wordpress_alb_dns_name" {
  value = aws_alb.wordpress_alb.dns_name
}

output "wordpress_rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3.bucket
}

output "wordpress_route53_zone_id" {
  value = aws_route53_zone.wordpress_route53.id
}
