# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Define variables for user-configurable values
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "List of availability zones"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for EC2 instances"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Instance class for RDS instance"
}

variable "domain_name" {
  type        = string
  default     = "example.com"
  description = "Domain name for Route 53 configuration"
}

# Create a VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "wordpress-vpc"
    Environment = "production"
  }
}

# Create public and private subnets
resource "aws_subnet" "public_subnets" {
  count             = length(var.availability_zones)
  cidr_block         = cidrsubnet(var.vpc_cidr, 8, count.index)
  vpc_id            = aws_vpc.wordpress_vpc.id
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "public-subnet-${count.index + 1}"
    Environment = "production"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.availability_zones)
  cidr_block         = cidrsubnet(var.vpc_cidr, 8, length(var.availability_zones) + count.index)
  vpc_id            = aws_vpc.wordpress_vpc.id
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "private-subnet-${count.index + 1}"
    Environment = "production"
  }
}

# Create an internet gateway and attach it to the VPC
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "wordpress-igw"
    Environment = "production"
  }
}

# Create a public route table and associate it with the public subnets
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "public-route-table"
    Environment = "production"
  }
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table_association" "public_subnets" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Create a private route table and associate it with the private subnets
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "private-route-table"
    Environment = "production"
  }
}

resource "aws_route_table_association" "private_subnets" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Create security groups for EC2 instances, RDS, and ELB
resource "aws_security_group" "wordpress_ec2_sg" {
  name        = "wordpress-ec2-sg"
  description = "Security group for WordPress EC2 instances"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS traffic from anywhere"
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
  }
  tags = {
    Name        = "wordpress-ec2-sg"
    Environment = "production"
  }
}

resource "aws_security_group" "wordpress_rds_sg" {
  name        = "wordpress-rds-sg"
  description = "Security group for WordPress RDS instance"
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
  }
  tags = {
    Name        = "wordpress-rds-sg"
    Environment = "production"
  }
}

resource "aws_security_group" "wordpress_elb_sg" {
  name        = "wordpress-elb-sg"
  description = "Security group for WordPress ELB"
  vpc_id      = aws_vpc.wordpress_vpc.id
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
  }
  tags = {
    Name        = "wordpress-elb-sg"
    Environment = "production"
  }
}

# Create EC2 instances for WordPress
resource "aws_instance" "wordpress_ec2" {
  count         = length(var.availability_zones)
  ami           = "ami-0c2ab3b8efb09f272"
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.wordpress_ec2_sg.id
  ]
  subnet_id = aws_subnet.private_subnets[count.index].id
  associate_public_ip_address = false
  ebs_optimized = true
  monitoring = true
  tags = {
    Name        = "wordpress-ec2-${count.index + 1}"
    Environment = "production"
  }
}

# Create an RDS instance for the WordPress database
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = var.rds_instance_class
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password"
  vpc_security_group_ids = [
    aws_security_group.wordpress_rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  storage_encrypted = true
  backup_retention_period = 12
  enabled_cloudwatch_logs_exports = ["mysql-slow-log", "mysql-error-log"]
  iam_database_authentication_enabled = true
  tags = {
    Name        = "wordpress-rds"
    Environment = "production"
  }
}

resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = aws_subnet.private_subnets.*.id
  tags = {
    Name        = "wordpress-rds-subnet-group"
    Environment = "production"
  }
}

# Create an Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_elb_sg.id]
  access_logs {
    bucket        = "elb-access-logs"
    bucket_prefix = "elb-access-logs"
    interval      = 60
  }
  tags = {
    Name        = "wordpress-elb"
    Environment = "production"
  }
}

# Create an Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  max_size                  = 5
  min_size                  = 1
  desired_capacity          = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = aws_subnet.private_subnets.*.id
  load_balancers = [aws_elb.wordpress_elb.name]
  tags = [
    {
      key                 = "Name"
      value               = "wordpress-asg"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = "production"
      propagate_at_launch = true
    },
  ]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = "ami-0c2ab3b8efb09f272"
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.wordpress_ec2_sg.id
  ]
  lifecycle {
    create_before_destroy = true
  }
}

# Create a CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [var.domain_name]
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
    acm_certificate_arn = aws_acm_certificate.wordpress_acm.arn
    ssl_support_method  = "sni-only"
    minimum_protocol_version = "TLSv1.2_2018"
  }
  logging_config {
    bucket = "cloudfront-logs.s3.amazonaws.com"
    prefix = "cloudfront-logs"
    include_cookies = true
  }
  tags = {
    Name        = "wordpress-cfd"
    Environment = "production"
  }
}

resource "aws_acm_certificate" "wordpress_acm" {
  domain_name       = var.domain_name
  validation_method = "DNS"
  tags = {
    Name        = "wordpress-acm"
    Environment = "production"
  }
}

resource "aws_route53_record" "wordpress_dns" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cfd.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cfd.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
  tags = {
    Name        = "wordpress-zone"
    Environment = "production"
  }
}

# Create an S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_s3" {
  bucket        = var.domain_name
  acl           = "private"
  force_destroy = true
  versioning {
    enabled = true
  }
  logging {
    target_bucket = "s3-logs"
    target_prefix = "s3-logs"
  }
  tags = {
    Name        = "wordpress-s3"
    Environment = "production"
  }
}

# Create a Flow Log for the VPC
resource "aws_flow_log" "wordpress_vpc_flow_log" {
  iam_role_arn    = aws_iam_role.wordpress_vpc_flow_log_role.arn
  log_destination = aws_s3_bucket.wordpress_vpc_flow_log_bucket.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.wordpress_vpc.id
}

resource "aws_iam_role" "wordpress_vpc_flow_log_role" {
  name        = "wordpress-vpc-flow-log-role"
  description = "Role for VPC Flow Log"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_s3_bucket" "wordpress_vpc_flow_log_bucket" {
  bucket        = "wordpress-vpc-flow-log-bucket"
  force_destroy = true
}

resource "aws_s3_bucket_policy" "wordpress_vpc_flow_log_bucket_policy" {
  bucket = aws_s3_bucket.wordpress_vpc_flow_log_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSFlowLogDelivery"
        Effect    = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action = [
          "s3:PutObject",
        ]
        Resource = "${aws_s3_bucket.wordpress_vpc_flow_log_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
    ]
  })
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
  value       = aws_s3_bucket.wordpress_s3.id
  description = "The name of the WordPress S3 bucket"
}

output "wordpress_cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.wordpress_cfd.id
  description = "The ID of the WordPress CloudFront distribution"
}

output "wordpress_route53_zone_id" {
  value       = aws_route53_zone.wordpress_zone.id
  description = "The ID of the WordPress Route 53 zone"
}
