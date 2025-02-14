# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Define variables
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for VPC"
}

variable "public_subnets_cidr_blocks" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "CIDR blocks for public subnets"
}

variable "private_subnets_cidr_blocks" {
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
  description = "CIDR blocks for private subnets"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
  description = "Availability zones for subnets"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for EC2 instances"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c2ab3b8efb09f272"
  description = "ID of the AMI to use for EC2 instances"
}

# Create VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name        = "WordPressVPC"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create subnets
resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnets_cidr_blocks)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnets_cidr_blocks[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PublicSubnet${count.index + 1}"
    Environment = "dev"
    Project     = "wordpress"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnets_cidr_blocks)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnets_cidr_blocks[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PrivateSubnet${count.index + 1}"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create route tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = "dev"
    Project     = "wordpress"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create routes
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Associate subnets with route tables
resource "aws_route_table_association" "public_subnets_association" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnets_association" {
  count          = length(aws_subnet.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Create security groups
resource "aws_security_group" "wordpress_sg" {
  name        = "WordPressSG"
  description = "Security group for WordPress instances"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow HTTP traffic from within the VPC"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow SSH traffic from within the VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outgoing traffic"
  }

  tags = {
    Name        = "WordPressSG"
    Environment = "dev"
    Project     = "wordpress"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "RDSSG"
  description = "Security group for RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
    description = "Allow MySQL traffic from WordPress instances"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outgoing traffic"
  }

  tags = {
    Name        = "RDSSG"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create EC2 instances
resource "aws_instance" "wordpress_instance" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  subnet_id = aws_subnet.public_subnets[0].id
  key_name               = "wordpress_key"
  user_data              = file("wordpress.sh")
  associate_public_ip_address = false
  monitoring = true
  ebs_optimized = true
  tags = {
    Name        = "WordPressInstance"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create RDS instance
resource "aws_db_instance" "wordpress_rds" {
  identifier           = "wordpress-rds"
  instance_class       = "db.t2.micro"
  engine               = "mysql"
  engine_version       = "8.0.23"
  username             = "wordpress"
  password             = random_password.rds_password.result
  allocated_storage    = 20
  storage_type         = "gp2"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  parameter_group_name = aws_db_parameter_group.wordpress_db_parameter_group.name
  publicly_accessible  = false
  skip_final_snapshot  = true
  storage_encrypted = true
  backup_retention_period = 12
  iam_database_authentication_enabled = true
  tags = {
    Name        = "WordPressRDS"
    Environment = "dev"
    Project     = "wordpress"
  }
}

resource "random_password" "rds_password" {
  length = 16
  special = true
}

# Create DB subnet group
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private_subnets.*.id
  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create DB parameter group
resource "aws_db_parameter_group" "wordpress_db_parameter_group" {
  name   = "wordpress-db-parameter-group"
  family = "mysql8.0"
  parameter {
    name  = "character_set_server"
    value = "utf8"
  }
  tags = {
    Name        = "WordPressDBParameterGroup"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_sg.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  access_logs {
    bucket        = aws_s3_bucket.wordpress_s3.id
    bucket_prefix  = "elb-logs"
    interval      = 60
  }

  tags = {
    Name        = "WordPressELB"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  min_size                  = 1
  max_size                  = 3
  desired_capacity          = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id
  load_balancers            = [aws_elb.wordpress_elb.name]

  tags = [
    {
      key                 = "Name"
      value               = "WordPressASG"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = "dev"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = "wordpress"
      propagate_at_launch = true
    }
  ]
}

# Create Launch Configuration
resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.wordpress_sg.id]
  key_name               = "wordpress_key"
  user_data              = file("wordpress.sh")
  ebs_optimized = true

  lifecycle {
    create_before_destroy = true
  }
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cloudfront" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-elb"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "https-only"
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

  logging_config {
    bucket = aws_s3_bucket.wordpress_s3.id
    prefix = "cloudfront-logs/"
  }

  tags = {
    Name        = "WordPressCloudFront"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create ACM certificate
resource "aws_acm_certificate" "wordpress_acm" {
  domain_name       = "example.com"
  validation_method = "DNS"
  tags = {
    Name        = "WordPressACM"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create Route 53 record
resource "aws_route53_record" "wordpress_route53" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cloudfront.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cloudfront.zone_id
    evaluate_target_health = false
  }
}

# Create Route 53 zone
resource "aws_route53_zone" "wordpress_route53_zone" {
  name = "example.com"
  tags = {
    Name        = "WordPressRoute53Zone"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create S3 bucket
resource "aws_s3_bucket" "wordpress_s3" {
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
    target_bucket = aws_s3_bucket.wordpress_s3.id
    target_prefix = "logs/"
  }

  tags = {
    Name        = "WordPressS3Bucket"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create CloudWatch log group
resource "aws_cloudwatch_log_group" "wordpress_log_group" {
  name = "wordpress-log-group"
  retention_in_days = 7
  tags = {
    Name        = "WordPressLogGroup"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create CloudWatch metric alarm
resource "aws_cloudwatch_metric_alarm" "wordpress_alarm" {
  alarm_name                = "wordpress-alarm"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = "2"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "300"
  statistic                 = "Average"
  threshold                 = "80"
  alarm_description         = "Alarm when CPU utilization is greater than 80%"
  insufficient_data_actions = []
  tags = {
    Name        = "WordPressAlarm"
    Environment = "dev"
    Project     = "wordpress"
  }
}

output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
  description = "The DNS name of the WordPress ELB"
}

output "wordpress_cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cloudfront.domain_name
  description = "The domain name of the WordPress CloudFront distribution"
}

output "wordpress_route53_name" {
  value = aws_route53_record.wordpress_route53.name
  description = "The name of the WordPress Route 53 record"
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3.bucket
  description = "The name of the WordPress S3 bucket"
}

output "wordpress_log_group_name" {
  value = aws_cloudwatch_log_group.wordpress_log_group.name
  description = "The name of the WordPress CloudWatch log group"
}
