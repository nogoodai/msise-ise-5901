provider "aws" {
  region = "us-west-2"
}

variable "vpc_cidr_block" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["us-west-2a", "us-west-2b"]
}

variable "ami_id" {
  type    = string
  default = "ami-076ce73a5f2173b9d"
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

variable "rds_instance_class" {
  type    = string
  default = "db.t2.small"
}

variable "instance_count" {
  type    = number
  default = 2
}

# Networking
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "public_subnets" {
  count = length(var.azs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, count.index)
  availability_zone = var.azs[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name        = "PublicSubnet${count.index + 1}"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private_subnets" {
  count = length(var.azs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, length(var.azs) + count.index)
  availability_zone = var.azs[count.index]
  tags = {
    Name        = "PrivateSubnet${count.index + 1}"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "IGW"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Security Groups
resource "aws_security_group" "web_server_sg" {
  name        = "WordPressWebServerSG"
  description = "Allow incoming traffic on HTTP and HTTPS ports"
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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WordPressWebServerSG"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "db_sg" {
  name        = "WordPressDBSG"
  description = "Allow incoming traffic on MySQL port"
  vpc_id      = aws_vpc.wordpress_vpc.id

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
    Name        = "WordPressDBSG"
    Environment = "production"
    Project     = "WordPress"
  }
}

# EC2 Instances
resource "aws_instance" "wordpress_instances" {
  count = var.instance_count
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id = aws_subnet.public_subnets[count.index].id
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  key_name               = "wordpress-key"

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update
              sudo apt install apache2 -y
              sudo apt install mysql-server -y
              sudo apt install php7.4 -y
              sudo apt install php7.4-mysql -y
              EOF

  tags = {
    Name        = "WordPressInstance${count.index + 1}"
    Environment = "production"
    Project     = "WordPress"
  }
}

# RDS Instance
resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = var.rds_instance_class
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password"
  parameter_group_name = "default.mysql8.0"
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.wordpress_db_subnet_group.name
  multi_az = true

  tags = {
    Name        = "WordPressDB"
    Environment = "production"
    Project     = "WordPress"
  }
}

# DB Subnet Group
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private_subnets.*.id

  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = "production"
    Project     = "WordPress"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.web_server_sg.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  tags = {
    Name        = "WordPressELB"
    Environment = "production"
    Project     = "WordPress"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  min_size                  = 2
  max_size                  = 5
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id
  health_check_type         = "EC2"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "WordPressASG"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "production"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = "WordPress"
    propagate_at_launch = true
  }
}

# Launch Configuration
resource "aws_launch_configuration" "wordpress_lc" {
  name            = "wordpress-lc"
  image_id        = var.ami_id
  instance_type   = var.instance_type
  security_groups = [aws_security_group.web_server_sg.id]
  key_name        = "wordpress-key"

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update
              sudo apt install apache2 -y
              sudo apt install mysql-server -y
              sudo apt install php7.4 -y
              sudo apt install php7.4-mysql -y
              EOF
}

# S3 Bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-bucket"
  acl    = "private"

  tags = {
    Name        = "WordPressS3Bucket"
    Environment = "production"
    Project     = "WordPress"
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_s3_bucket.wordpress_bucket.bucket_regional_domain_name
    origin_id   = "wordpress-bucket"
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-bucket"

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

# Route 53
resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = aws_elb.wordpress_elb.dns_name
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

# CloudWatch
resource "aws_cloudwatch_metric_alarm" "wordpress_seconds" {
  alarm_name          = "wp-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  actions_enabled     = true
  alarm_actions       = [aws_sns_topic.wordpress_sns_topic.arn]
  insufficient_data_actions = []
  ok_actions           = []
}

resource "aws_sns_topic" "wordpress_sns_topic" {
  name = "wordpress-sns-topic"
}
