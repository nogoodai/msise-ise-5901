provider "aws" {
  region = "us-west-2"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for EC2 instances"
}

variable "key_pair_name" {
  type        = string
  default     = "wordpress-key"
  description = "Name of the key pair for EC2 instances"
}

variable "domain_name" {
  type        = string
  default     = "example.com"
  description = "Domain name for Route 53 and CloudFront"
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

# Create internet gateway
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressInternetGateway"
  }
}

# Create route tables
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

# Create route table associations
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

# Create routes
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
}

# Create security groups
resource "aws_security_group" "ec2_security_group" {
  name        = "WordPressEc2SecurityGroup"
  description = "Security group for EC2 instances"
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

  ingress {
    description = "Allow SSH from specific IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["1.1.1.1/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds_security_group" {
  name        = "WordPressRdsSecurityGroup"
  description = "Security group for RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "Allow MySQL from EC2 security group"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.ec2_security_group.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "elb_security_group" {
  name        = "WordPressElbSecurityGroup"
  description = "Security group for ELB"
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
}

# Create EC2 instances
resource "aws_instance" "wordpress_ec2" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.ec2_security_group.id]
  subnet_id = aws_subnet.public_subnet_1.id
  key_name               = var.key_pair_name
  user_data              = file("${path.module}/user-data.sh")

  tags = {
    Name = "WordPressEc2Instance"
  }
}

# Create RDS instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password"
  parameter_group_name = "default.mysql5.7"
  vpc_security_group_ids = [aws_security_group.rds_security_group.id]
  db_subnet_group_name = "wordpress-rds-subnet-group"
  publicly_accessible  = false
  skip_final_snapshot  = true

  tags = {
    Name = "WordPressRdsInstance"
  }
}

# Create ELB
resource "aws_alb" "wordpress_alb" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.elb_security_group.id]
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]

  tags = {
    Name = "WordPressAlb"
  }
}

# Create target group
resource "aws_alb_target_group" "wordpress_target_group" {
  name     = "wordpress-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    interval            = 10
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name = "WordPressTargetGroup"
  }
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cloudfront" {
  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = "S3Origin"

    custom_header {
      name  = "X-Forwarded-Proto"
      value = "https"
    }
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"

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
      restriction_type = "whitelist"
      locations        = []
    }
  }

  tags = {
    Name = "WordPressCloudFrontDistribution"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Create S3 bucket
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = var.domain_name

  tags = {
    Name        = var.domain_name
    Environment = "Production"
  }
}

# Create Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_route53_zone" {
  name = var.domain_name
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cloudfront.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cloudfront.zone_id
    evaluate_target_health = false
  }
}

# Create Auto Scaling group
resource "aws_autoscaling_group" "wordpress_autoscaling_group" {
  name                      = "wordpress-autoscaling-group"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity          = 1
  launch_configuration      = aws_launch_configuration.wordpress_launch_configuration.name
  vpc_zone_identifier       = aws_subnet.public_subnet_1.id

  tag {
    key                 = "Name"
    value               = "WordPressAutoscalingGroup"
    propagate_at_launch = true
  }
}

# Create launch configuration
resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name          = "wordpress-launch-configuration"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  key_name               = var.key_pair_name

  security_groups = [aws_security_group.ec2_security_group.id]

  user_data = file("${path.module}/user-data.sh")
}

# Create CloudWatch logs
resource "aws_cloudwatch_log_group" "wordpress_cloudwatch_log_group" {
  name = "wordpress-cloudwatch-log-group"
}

resource "aws_cloudwatch_log_stream" "wordpress_cloudwatch_log_stream" {
  name           = "wordpress-cloudwatch-log-stream"
  log_group_name = aws_cloudwatch_log_group.wordpress_cloudwatch_log_group.name
}

# Create CloudWatch metric alarms
resource "aws_cloudwatch_metric_alarm" "wordpress_cpu_alarm" {
  alarm_name          = "wordpress-cpu-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "50"

  alarm_description = "This metric alarm monitors the CPU utilization of the EC2 instance"
  alarm_actions     = [aws_sns_topic.wordpress_sns_topic.arn]
}

resource "aws_sns_topic" "wordpress_sns_topic" {
  name = "wordpress-sns-topic"
}

output "wordpress_vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "wordpress_ec2_id" {
  value = aws_instance.wordpress_ec2.id
}

output "wordpress_rds_id" {
  value = aws_db_instance.wordpress_rds.id
}

output "wordpress_alb_id" {
  value = aws_alb.wordpress_alb.id
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3_bucket.bucket
}

output "wordpress_cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.wordpress_cloudfront.id
}

output "wordpress_route53_zone_id" {
  value = aws_route53_zone.wordpress_route53_zone.zone_id
}

output "wordpress_autoscaling_group_id" {
  value = aws_autoscaling_group.wordpress_autoscaling_group.id
}
