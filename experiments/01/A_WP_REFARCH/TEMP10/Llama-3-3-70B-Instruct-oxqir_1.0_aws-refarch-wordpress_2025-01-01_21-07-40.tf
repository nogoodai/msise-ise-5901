provider "aws" {
  region = "us-west-2"
}

variable "wp_vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "wp_azs" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
  description = "Availability zones for the VPC"
}

variable "wp_vpc_name" {
  type        = string
  default     = "WordPressVPC"
  description = "Name of the VPC"
}

variable "wp_rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Instance class for the RDS instance"
}

variable "wp_ec2_instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for the EC2 instances"
}

variable "wp_s3_bucket_name" {
  type        = string
  default     = "wordpress-static-assets"
  description = "Name of the S3 bucket for static assets"
}

variable "wp_domain_name" {
  type        = string
  default     = "example.com"
  description = "Domain name for the WordPress site"
}

# VPC and networking resources
resource "aws_vpc" "wp_vpc" {
  cidr_block = var.wp_vpc_cidr
  tags = {
    Name = var.wp_vpc_name
  }
}

resource "aws_subnet" "wp_public_subnets" {
  count             = length(var.wp_azs)
  vpc_id            = aws_vpc.wp_vpc.id
  cidr_block        = cidrsubnet(var.wp_vpc_cidr, 8, count.index)
  availability_zone = var.wp_azs[count.index]
  tags = {
    Name = "Public Subnet ${count.index + 1}"
  }
}

resource "aws_subnet" "wp_private_subnets" {
  count             = length(var.wp_azs)
  vpc_id            = aws_vpc.wp_vpc.id
  cidr_block        = cidrsubnet(var.wp_vpc_cidr, 8, length(var.wp_azs) + count.index)
  availability_zone = var.wp_azs[count.index]
  tags = {
    Name = "Private Subnet ${count.index + 1}"
  }
}

resource "aws_internet_gateway" "wp_igw" {
  vpc_id = aws_vpc.wp_vpc.id
  tags = {
    Name = "WordPress IGW"
  }
}

resource "aws_route_table" "wp_public_rt" {
  vpc_id = aws_vpc.wp_vpc.id
  tags = {
    Name = "Public Route Table"
  }
}

resource "aws_route" "wp_public_route" {
  route_table_id         = aws_route_table.wp_public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wp_igw.id
}

resource "aws_route_table_association" "wp_public_assoc" {
  count          = length(var.wp_azs)
  subnet_id      = aws_subnet.wp_public_subnets[count.index].id
  route_table_id = aws_route_table.wp_public_rt.id
}

# Security groups
resource "aws_security_group" "wp_web_sg" {
  name        = "WordPress Web SG"
  description = "Allow incoming HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.wp_vpc.id

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
}

resource "aws_security_group" "wp_db_sg" {
  name        = "WordPress DB SG"
  description = "Allow incoming MySQL traffic"
  vpc_id      = aws_vpc.wp_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wp_web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "wp_elb_sg" {
  name        = "WordPress ELB SG"
  description = "Allow incoming HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.wp_vpc.id

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
}

# EC2 instances for WordPress
resource "aws_instance" "wp_instance" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.wp_ec2_instance_type
  vpc_security_group_ids = [
    aws_security_group.wp_web_sg.id
  ]
  subnet_id = aws_subnet.wp_private_subnets[0].id
  tags = {
    Name = "WordPress Instance"
  }
}

# RDS instance for WordPress database
resource "aws_db_instance" "wp_db" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = var.wp_rds_instance_class
  db_name              = "wordpressdb"
  username             = "wordpressuser"
  password             = "wordpresspass"
  vpc_security_group_ids = [
    aws_security_group.wp_db_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wp_db_subnet_group.name
  tags = {
    Name = "WordPress DB"
  }
}

resource "aws_db_subnet_group" "wp_db_subnet_group" {
  name       = "wordpress_db_subnet_group"
  subnet_ids = [for subnet in aws_subnet.wp_private_subnets : subnet.id]
  tags = {
    Name = "WordPress DB Subnet Group"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wp_elb" {
  name            = "wordpress-elb"
  subnets         = [for subnet in aws_subnet.wp_public_subnets : subnet.id]
  security_groups = [aws_security_group.wp_elb_sg.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  listener {
    instance_port      = 443
    instance_protocol  = "https"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  }

  tags = {
    Name = "WordPress ELB"
  }
}

# Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wp_asg" {
  name                      = "wordpress-asg"
  max_size                  = 5
  min_size                  = 2
  desired_capacity          = 3
  vpc_zone_identifier       = [for subnet in aws_subnet.wp_private_subnets : subnet.id]
  launch_template {
    id      = aws_launch_template.wp_lt.id
    version = aws_launch_template.wp_lt.latest_version_number
  }
}

resource "aws_launch_template" "wp_lt" {
  name          = "wordpress-launch-template"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.wp_ec2_instance_type
  vpc_security_group_ids = [
    aws_security_group.wp_web_sg.id
  ]
  key_name               = "wordpress-key"
  user_data              = base64encode(file("${path.module}/wp_user_data.sh"))
  tags = {
    Name = "WordPress Launch Template"
  }
}

# CloudFront distribution for content delivery
resource "aws_cloudfront_distribution" "wp_cf" {
  origin {
    domain_name = aws_s3_bucket.wp_bucket.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.wp_bucket.id}"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases = [
    var.wp_domain_name
  ]

  viewer_certificate {
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "sni-only"
  }

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.wp_bucket.id}"

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
    Name = "WordPress CloudFront"
  }
}

# S3 bucket for static assets
resource "aws_s3_bucket" "wp_bucket" {
  bucket = var.wp_s3_bucket_name
  acl    = "public-read"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource = [
          "arn:aws:s3:::${var.wp_s3_bucket_name}/*",
        ]
      },
    ]
  })

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET", "HEAD", "DELETE"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }

  tags = {
    Name = "WordPress Static Assets"
  }
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wp_zone" {
  name = var.wp_domain_name
}

resource "aws_route53_record" "wp_alb_record" {
  zone_id = aws_route53_zone.wp_zone.id
  name    = var.wp_domain_name
  type    = "A"

  alias {
    name                   = aws_elb.wp_elb.dns_name
    zone_id                = aws_elb.wp_elb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "wp_cf_record" {
  zone_id = aws_route53_zone.wp_zone.id
  name    = ""
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wp_cf.domain_name
    zone_id                = aws_cloudfront_distribution.wp_cf.zone_id
    evaluate_target_health = false
  }
}
