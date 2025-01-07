# Configure the AWS Provider
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
resource "aws_subnet" "public_subnet" {
  cidr_block = "10.0.1.0/24"
  vpc_id     = aws_vpc.wordpress_vpc.id
  availability_zone = "us-west-2a"
  tags = {
    Name = "Public-Subnet"
  }
}

resource "aws_subnet" "private_subnet" {
  cidr_block = "10.0.2.0/24"
  vpc_id     = aws_vpc.wordpress_vpc.id
  availability_zone = "us-west-2a"
  tags = {
    Name = "Private-Subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPress-IGW"
  }
}

# Route Tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "Public-Route-Table"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "Private-Route-Table"
  }
}

# Associate Route Tables with Subnets
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

# Security Groups
resource "aws_security_group" "web_server_sg" {
  name        = "wordpress-web-server-sg"
  description = "Allow HTTP, HTTPS, and SSH"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
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
}

resource "aws_security_group" "db_sg" {
  name        = "wordpress-db-sg"
  description = "Allow MySQL"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "MySQL"
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
}

# EC2 Instances for WordPress
resource "aws_instance" "wordpress_instance" {
  ami           = "ami-0c2ab3b8efb09f272"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  key_name               = "wordpress-key"

  tags = {
    Name = "WordPress-Instance"
  }
}

# RDS Instance for WordPress Database
resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  username             = "admin"
  password             = "password123"
  db_name              = "wordpressdb"
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  skip_final_snapshot  = true

  tags = {
    Name = "WordPress-DB"
  }
}

# Elastic Load Balancer
resource "aws_alb" "wordpress_alb" {
  name            = "wordpress-alb"
  subnets         = [aws_subnet.public_subnet.id]
  security_groups = [aws_security_group.web_server_sg.id]

  tags = {
    Name = "WordPress-ALB"
  }
}

resource "aws_alb_target_group" "wordpress_target_group" {
  name     = "wordpress-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  tags = {
    Name = "WordPress-Target-Group"
  }
}

resource "aws_alb_listener" "wordpress_listener" {
  load_balancer_arn = aws_alb.wordpress_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.wordpress_target_group.arn
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
  launch_configuration      = aws_launch_configuration.wordpress_lc.name

  vpc_zone_identifier = aws_subnet.private_subnet.id

  tags = [
    {
      key                 = "Name"
      value               = "WordPress-Instance"
      propagate_at_launch = true
    },
  ]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name                            = "wordpress-lc"
  image_id                      = "ami-0c2ab3b8efb09f272"
  instance_type                 = "t2.micro"
  security_groups               = [aws_security_group.web_server_sg.id]
  key_name                      = "wordpress-key"

  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = "wordpressOrigin"
  }

  enabled = true

  default_root_object = "index.html"

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
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-bucket"
  acl    = "private"

  tags = {
    Name = "WordPress-Bucket"
  }
}

resource "aws_s3_bucket_policy" "wordpress_bucket_policy" {
  bucket = aws_s3_bucket.wordpress_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource = [
          aws_s3_bucket.wordpress_bucket.arn,
          "${aws_s3_bucket.wordpress_bucket.arn}/*",
        ]
      },
    ]
  })
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_alb.wordpress_alb.dns_name
    zone_id               = aws_alb.wordpress_alb.zone_id
    evaluate_target_health = false
  }
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "wordpress_alarm" {
  alarm_name                = "WordPress-Alarm"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = "2"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "300"
  statistic                 = "Average"
  threshold                 = "70"
  alarm_description         = "This metric alarm monitors the CPU utilization of the WordPress instances"
  actions_enabled           = true
  alarm_actions             = [aws_sns_topic.wordpress_topic.arn]
  insufficient_data_actions = []
  ok_actions                = []
}

resource "aws_sns_topic" "wordpress_topic" {
  name = "WordPress-Topic"
}

resource "aws_sns_topic_subscription" "wordpress_subscription" {
  topic_arn = aws_sns_topic.wordpress_topic.arn
  protocol  = "email"
  endpoint  = "example@example.com"
}

output "CloudFrontDistributionId" {
  value = aws_cloudfront_distribution.wordpress_distribution.id
}

output "Route53DomainName" {
  value = aws_route53_record.wordpress_record.name
}

output "ALBDNSName" {
  value = aws_alb.wordpress_alb.dns_name
}

output "EC2InstanceID" {
  value = aws_instance.wordpress_instance.id
}

output "RDSInstanceID" {
  value = aws_db_instance.wordpress_db.id
}

output "S3BucketName" {
  value = aws_s3_bucket.wordpress_bucket.id
}

output "VPCID" {
  value = aws_vpc.wordpress_vpc.id
}
