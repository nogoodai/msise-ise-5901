provider "aws" {
  region = "us-west-2"
}

variable "wordpress_vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}

variable "wordpress_subnet_cidr" {
  type        = string
  default     = "10.0.1.0/24"
  description = "The CIDR block for the subnet"
}

variable "wordpress_private_subnet_cidr" {
  type        = string
  default     = "10.0.2.0/24"
  description = "The CIDR block for the private subnet"
}

variable "wordpress_instance_type" {
  type        = string
  default     = "t2.micro"
  description = "The instance type for the EC2 instance"
}

variable "wordpress_rds_instance_class" {
  type        = string
  default     = "db.t2.micro"
  description = "The instance class for the RDS instance"
}

variable "wordpress_rds_username" {
  type        = string
  sensitive   = true
  description = "The username for the RDS instance"
}

variable "wordpress_rds_password" {
  type        = string
  sensitive   = true
  description = "The password for the RDS instance"
}

variable "wordpress_rds_backup_retention_period" {
  type        = number
  default     = 12
  description = "The backup retention period for the RDS instance"
}

variable "wordpress_elb_name" {
  type        = string
  default     = "wordpress-elb"
  description = "The name of the ELB"
}

variable "wordpress_asg_name" {
  type        = string
  default     = "wordpress-asg"
  description = "The name of the ASG"
}

# VPC Configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.wordpress_vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Subnet Configuration
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.wordpress_subnet_cidr
  availability_zone = "us-west-2a"
  tags = {
    Name        = "PublicSubnet"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.wordpress_private_subnet_cidr
  availability_zone = "us-west-2b"
  tags = {
    Name        = "PrivateSubnet"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Internet Gateway Configuration
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Route Table Configuration
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Route Configuration
resource "aws_route" "public_internet_gateway_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Subnet Association
resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnet_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

# Security Group Configuration
resource "aws_security_group" "wordpress_ec2_sg" {
  name        = "WordPressEC2SG"
  description = "Security Group for WordPress EC2 instances"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP traffic from anywhere"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH traffic from anywhere"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outgoing traffic"
  }

  tags = {
    Name        = "WordPressEC2SG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "wordpress_rds_sg" {
  name        = "WordPressRDSSG"
  description = "Security Group for WordPress RDS instances"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_ec2_sg.id]
    description     = "Allow MySQL traffic from EC2 instances"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outgoing traffic"
  }

  tags = {
    Name        = "WordPressRDSSG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "wordpress_elb_sg" {
  name        = "WordPressELBSG"
  description = "Security Group for WordPress ELB"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP traffic from anywhere"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outgoing traffic"
  }

  tags = {
    Name        = "WordPressELBSG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# EC2 Configuration
resource "aws_instance" "wordpress_ec2" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.wordpress_instance_type
  vpc_security_group_ids = [
    aws_security_group.wordpress_ec2_sg.id
  ]
  key_name               = "wordpress-key"
  subnet_id              = aws_subnet.public_subnet.id
  user_data              = file("${path.module}/wordpress-install.sh")
  associate_public_ip_address = false
  monitoring              = true
  ebs_optimized            = true
  tags = {
    Name        = "WordPressEC2"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# RDS Configuration
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = var.wordpress_rds_instance_class
  name                 = "wordpressdb"
  username             = var.wordpress_rds_username
  password             = var.wordpress_rds_password
  vpc_security_group_ids = [
    aws_security_group.wordpress_rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  storage_encrypted     = true
  backup_retention_period = var.wordpress_rds_backup_retention_period
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]
  tags = {
    Name        = "WordPressRDS"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = [aws_subnet.private_subnet.id]
  tags = {
    Name        = "WordPressRDSSubnetGroup"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# ELB Configuration
resource "aws_elb" "wordpress_elb" {
  name            = var.wordpress_elb_name
  subnets         = [aws_subnet.public_subnet.id]
  security_groups = [aws_security_group.wordpress_elb_sg.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  access_logs {
    bucket        = "wordpress-elb-logs"
    bucket_prefix = "elb-logs"
    interval      = 60
  }

  tags = {
    Name        = "WordPressELB"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Auto Scaling Group Configuration
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = var.wordpress_asg_name
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  launch_template {
    id      = aws_launch_template.wordpress_launch_template.id
    version = "$Latest"
  }
  load_balancers = [aws_elb.wordpress_elb.name]
  tags = [
    {
      key                 = "Name"
      value               = "WordPressASG"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = "Production"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = "WordPress"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_template" "wordpress_launch_template" {
  name = "wordpress-launch-template"

  image_id = "ami-0c94855ba95c71c99"

  instance_type = var.wordpress_instance_type

  key_name = "wordpress-key"

  vpc_security_group_ids = [
    aws_security_group.wordpress_ec2_sg.id
  ]

  user_data = file("${path.module}/wordpress-install.sh")

  tags = {
    Name        = "WordPressLaunchTemplate"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# CloudFront Configuration
resource "aws_cloudfront_distribution" "wordpress_cdn" {
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
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  }

  logging_config {
    bucket = "wordpress-cdn-logs.s3.amazonaws.com"
    prefix = "cdn-logs/"
  }

  tags = {
    Name        = "WordPressCDN"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# S3 Bucket Configuration
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = "wordpress-s3-bucket"
  acl    = "private"

  versioning {
    enabled = true
  }

  logging {
    target_bucket = "wordpress-s3-logs"
    target_prefix = "s3-logs/"
  }

  tags = {
    Name        = "WordPressS3Bucket"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Route 53 Configuration
resource "aws_route53_zone" "wordpress_route53_zone" {
  name = "wordpress.example.com"
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.zone_id
  name    = "wordpress.example.com"
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

output "elb_dns_name" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "The DNS name of the ELB"
}

output "rds_instance_endpoint" {
  value       = aws_db_instance.wordpress_rds.endpoint
  description = "The endpoint of the RDS instance"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.wordpress_s3_bucket.bucket
  description = "The name of the S3 bucket"
}

output "cloudfront_distribution_domain_name" {
  value       = aws_cloudfront_distribution.wordpress_cdn.domain_name
  description = "The domain name of the CloudFront distribution"
}
