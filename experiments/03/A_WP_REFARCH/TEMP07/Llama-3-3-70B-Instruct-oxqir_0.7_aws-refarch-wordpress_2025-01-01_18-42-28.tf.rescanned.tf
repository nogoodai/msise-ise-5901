# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Define variables for the VPC
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}

variable "vpc_name" {
  type        = string
  default     = "wordpress-vpc"
  description = "The name of the VPC"
}

variable "public_subnet_cidr" {
  type        = string
  default     = "10.0.1.0/24"
  description = "The CIDR block for the public subnet"
}

variable "private_subnet_cidr" {
  type        = string
  default     = "10.0.2.0/24"
  description = "The CIDR block for the private subnet"
}

variable "availability_zone" {
  type        = string
  default     = "us-west-2a"
  description = "The availability zone for the subnets"
}

# Create VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = var.vpc_name
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create subnets
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidr
  availability_zone = var.availability_zone
  tags = {
    Name        = "public-subnet"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone
  tags = {
    Name        = "private-subnet"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "wordpress-igw"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create route tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "public-route-table"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "private-route-table"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create route table associations
resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnet_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

# Create routes
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Create security groups
resource "aws_security_group" "wordpress_sg" {
  name        = "wordpress-sg"
  description = "Allow HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP traffic from anywhere"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS traffic from anywhere"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "wordpress-sg"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Allow MySQL traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
    description     = "Allow MySQL traffic from the WordPress security group"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "rds-sg"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create RDS instance
resource "aws_db_instance" "wordpress_rds" {
  identifier           = "wordpress-rds"
  instance_class       = "db.t2.small"
  engine               = "mysql"
  engine_version       = "8.0.23"
  allocated_storage    = 20
  storage_type         = "gp2"
  parameter_group_name = "default.mysql8.0"
  db_name              = "wordpress"
  username             = "admin"
  password             = "password"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  availability_zone   = var.availability_zone
  multi_az            = true
  storage_encrypted   = true
  backup_retention_period = 12
  iam_database_authentication_enabled = true
  skip_final_snapshot  = true
  tags = {
    Name        = "wordpress-rds"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create EC2 instances
resource "aws_instance" "wordpress_ec2" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  subnet_id = aws_subnet.private_subnet.id
  key_name               = "wordpress-key"
  user_data              = file("./wordpress_userdata.sh")
  associate_public_ip_address = false
  ebs_optimized = true
  monitoring = true
  tags = {
    Name        = "wordpress-ec2"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = [aws_subnet.public_subnet.id]
  security_groups = [aws_security_group.wordpress_sg.id]
  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 80
    lb_protocol        = "http"
  }
  listener {
    instance_port      = 443
    instance_protocol  = "https"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  }
  access_logs {
    bucket        = "wordpress-elb-logs"
    bucket_prefix = "wordpress-elb"
    interval      = 60
  }
  tags = {
    Name        = "wordpress-elb"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 1
  launch_configuration      = aws_launch_configuration.wordpress_launchconfig.name
  vpc_zone_identifier       = aws_subnet.private_subnet.id
  load_balancers            = [aws_elb.wordpress_elb.name]
  tags = {
    Name        = "wordpress-asg"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_launch_configuration" "wordpress_launchconfig" {
  name          = "wordpress-launchconfig"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.wordpress_sg.id]
  key_name               = "wordpress-key"
  user_data              = file("./wordpress_userdata.sh")
  ebs_optimized = true
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }
  enabled = true
  default_root_object = "index.html"
  aliases = ["example.com", "www.example.com"]
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-elb"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "redirect-to-https"
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "sni-only"
    minimum_protocol_version = "TLSv1.2_2019"
  }
  logging_config {
    bucket = "wordpress-cloudfront-logs.s3.amazonaws.com"
    prefix = "wordpress-cloudfront"
  }
  tags = {
    Name        = "wordpress-distribution"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create S3 bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "example-bucket"
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
  logging {
    target_bucket = "wordpress-s3-logs"
    target_prefix = "wordpress-s3/"
  }
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource = [
          "arn:aws:s3:::example-bucket/*",
        ]
      },
    ]
  })
  tags = {
    Name        = "example-bucket"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create Route 53 record
resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "example.com"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_distribution.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_distribution.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
  tags = {
    Name        = "example.com"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create CloudWatch dashboard
resource "aws_cloudwatch_dashboard" "wordpress_dashboard" {
  dashboard_name = "wordpress-dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        x    = 0
        y    = 0
        width = 12
        height = 6
        properties = {
          view = "timeSeries"
          stacked = false
          metrics = [
            {
              label = "CPUUtilization"
              id    = "cpu-metric"
              metric = "AWS/EC2/CPUUtilization"
              region = "us-west-2"
              stat   = "Average"
              period = 300
              dim = {
                name  = "InstanceId"
                value = aws_instance.wordpress_ec2.id
              }
            },
          ]
          title = "CPU Utilization"
        }
      },
    ]
  })
  tags = {
    Name        = "wordpress-dashboard"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create CloudWatch alarms
resource "aws_cloudwatch_metric_alarm" "wordpress_alarm" {
  alarm_name                = "wordpress-alarm"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = "1"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "300"
  statistic                 = "Average"
  threshold                = "80"
  alarm_description         = "CPU utilization is too high"
  alarm_actions             = [aws_sns_topic.wordpress_sns.arn]
  insufficient_data_actions = []
  ok_actions                = []
  dimensions = {
    InstanceId = aws_instance.wordpress_ec2.id
  }
  tags = {
    Name        = "wordpress-alarm"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_sns_topic" "wordpress_sns" {
  name = "wordpress-sns"
  kms_master_key_id = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
  tags = {
    Name        = "wordpress-sns"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create IAM roles and policies
resource "aws_iam_role" "wordpress_iam_role" {
  name        = "wordpress-iam-role"
  description = "IAM role for WordPress"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Effect = "Allow"
        Sid      = ""
      },
    ]
  })
  tags = {
    Name        = "wordpress-iam-role"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_iam_role_policy" "wordpress_iam_policy" {
  name   = "wordpress-iam-policy"
  role   = aws_iam_role.wordpress_iam_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::example-bucket",
          "arn:aws:s3:::example-bucket/*",
        ]
        Effect = "Allow"
      },
    ]
  })
}

# Create IAM instance profile
resource "aws_iam_instance_profile" "wordpress_iam_profile" {
  name = "wordpress-iam-profile"
  role = aws_iam_role.wordpress_iam_role.name
  tags = {
    Name        = "wordpress-iam-profile"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Output critical information
output "wordpress_elb_dns_name" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "The DNS name of the WordPress ELB"
}

output "wordpress_rds_endpoint" {
  value       = aws_db_instance.wordpress_rds.endpoint
  description = "The endpoint of the WordPress RDS instance"
}

output "wordpress_s3_bucket_name" {
  value       = aws_s3_bucket.wordpress_bucket.bucket
  description = "The name of the WordPress S3 bucket"
}

output "wordpress_route53_record_name" {
  value       = aws_route53_record.wordpress_record.name
  description = "The name of the WordPress Route 53 record"
}
