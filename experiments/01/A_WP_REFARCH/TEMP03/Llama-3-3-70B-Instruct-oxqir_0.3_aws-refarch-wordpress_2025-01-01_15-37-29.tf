# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Define variables for the configuration
variable "aws_region" {
  type        = string
  default     = "us-west-2"
  description = "AWS Region"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "VPC CIDR block"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "Public subnet CIDR blocks"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
  description = "Private subnet CIDR blocks"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "EC2 instance type"
}

variable "db_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "RDS instance class"
}

variable "domain_name" {
  type        = string
  default     = "example.com"
  description = "Domain name for Route 53"
}

# Create VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Create subnets
resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = "${var.aws_region}${count.index % 2 == 0 ? "a" : "b"}"
  tags = {
    Name        = "PublicSubnet${count.index}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = "${var.aws_region}${count.index % 2 == 0 ? "a" : "b"}"
  tags = {
    Name        = "PrivateSubnet${count.index}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Create internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Create route tables
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

# Create route table associations
resource "aws_route_table_association" "public_subnets" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnets" {
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
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
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
    Name        = "WordPressSG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "RDSSG"
  description = "Security group for RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "RDSSG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Create RDS instance
resource "aws_db_instance" "wordpress_rds" {
  instance_class = var.db_instance_class
  engine         = "mysql"
  engine_version = "8.0.28"
  username       = "wordpress"
  password       = "wordpress"
  vpc_security_group_ids = [
    aws_security_group.rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  tags = {
    Name        = "WordPressRDS"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Create DB subnet group
resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "WordPressRDSSubnetGroup"
  subnet_ids = [for subnet in aws_subnet.private_subnets : subnet.id]
  tags = {
    Name        = "WordPressRDSSubnetGroup"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Create EC2 instances
resource "aws_instance" "wordpress_ec2" {
  count         = 2
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.wordpress_sg.id
  ]
  subnet_id = aws_subnet.public_subnets[count.index].id
  tags = {
    Name        = "WordPressEC2${count.index}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Create Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = [for subnet in aws_subnet.public_subnets : subnet.id]
  security_groups = [aws_security_group.wordpress_sg.id]
  listener {
    lb_port       = 80
    lb_protocol   = "http"
    instance_port = 80
    instance_protocol = "http"
  }
  tags = {
    Name        = "WordPressELB"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Create Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  max_size                  = 5
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = [for subnet in aws_subnet.public_subnets : subnet.id]
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
    },
  ]
}

# Create Launch Configuration
resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.wordpress_sg.id
  ]
  user_data = file("${path.module}/wordpress.sh")
  lifecycle {
    create_before_destroy = true
  }
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [var.domain_name]
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.wordpress_acm.arn
    ssl_support_method  = "sni-only"
  }
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WordPressELB"
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
  tags = {
    Name        = "WordPressCFD"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Create ACM certificate
resource "aws_acm_certificate" "wordpress_acm" {
  domain_name       = var.domain_name
  validation_method = "DNS"
  tags = {
    Name        = "WordPressACM"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Create Route 53 record
resource "aws_route53_record" "wordpress_r53" {
  zone_id = aws_route53_zone.wordpress_r53_zone.id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cfd.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cfd.zone_id
    evaluate_target_health = false
  }
}

# Create Route 53 zone
resource "aws_route53_zone" "wordpress_r53_zone" {
  name = var.domain_name
  tags = {
    Name        = "WordPressR53Zone"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Create S3 bucket
resource "aws_s3_bucket" "wordpress_s3" {
  bucket = var.domain_name
  acl    = "private"
  tags = {
    Name        = "WordPressS3"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Output critical information
output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "wordpress_cfd_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cfd.domain_name
}

output "wordpress_r53_zone_id" {
  value = aws_route53_zone.wordpress_r53_zone.id
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3.bucket
}
