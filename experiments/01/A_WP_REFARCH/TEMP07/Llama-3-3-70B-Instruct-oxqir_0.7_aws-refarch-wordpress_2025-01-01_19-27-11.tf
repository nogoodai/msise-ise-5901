provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
}

variable "aws_availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
}

variable "db_instance_class" {
  type        = string
  default     = "db.t2.small"
}

variable "ec2_key_pair" {
  type        = string
  default     = "wordpress-key"
}

variable "domain_name" {
  type        = string
  default     = "example.com"
}

# VPC configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

resource "aws_subnet" "public_subnets" {
  count = length(var.aws_availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.aws_availability_zones[count.index]
  tags = {
    Name = "WordPressPublicSubnet${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count = length(var.aws_availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, length(var.aws_availability_zones) + count.index)
  availability_zone = var.aws_availability_zones[count.index]
  tags = {
    Name = "WordPressPrivateSubnet${count.index + 1}"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressPublicRouteTable"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table_association" "public_subnets_association" {
  count          = length(var.aws_availability_zones)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Security groups
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
    Name = "WordPressSG"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "RDS SG"
  description = "Security group for RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
  }

  tags = {
    Name = "RDS SG"
  }
}

# EC2 instances for WordPress
resource "aws_instance" "wordpress_instances" {
  count         = 2
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  subnet_id = aws_subnet.public_subnets[count.index].id
  key_name               = var.ec2_key_pair
  user_data = file("./wordpress_install.sh")

  tags = {
    Name = "WordPressInstance${count.index + 1}"
  }
}

# RDS instance for WordPress database
resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = var.db_instance_class
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password123"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  skip_final_snapshot  = true
  multi_az             = true
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress_db_subnet_group"
  subnet_ids = aws_subnet.private_subnets.*.id

  tags = {
    Name = "WordPressDBSubnetGroup"
  }
}

# Elastic Load Balancer
resource "aws_lb" "wordpress_elb" {
  name               = "WordPressELB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.wordpress_sg.id]
  subnets            = aws_subnet.public_subnets.*.id

  tags = {
    Name = "WordPressELB"
  }
}

resource "aws_lb_target_group" "wordpress_tg" {
  name     = "WordPressTG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 10
    timeout             = 5
    interval            = 10
    path                = "/healthcheck"
    port                = "traffic-port"
  }
}

resource "aws_lb_listener" "wordpress_listener" {
  load_balancer_arn = aws_lb.wordpress_elb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
    type             = "forward"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "WordPressASG"
  max_size            = 5
  min_size            = 2
  vpc_zone_identifier = aws_subnet.public_subnets.*.id
  target_group_arns   = [aws_lb_target_group.wordpress_tg.arn]

  launch_template {
    id      = aws_launch_template.wordpress_lt.id
    version = aws_launch_template.wordpress_lt.latest_version_number
  }
}

resource "aws_launch_template" "wordpress_lt" {
  name                 = "WordPressLT"
  image_id             = "ami-0c55b159cbfafe1f0"
  instance_type        = var.instance_type
  key_name             = var.ec2_key_pair
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  user_data = base64encode(file("./wordpress_install.sh"))
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_lb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"

    custom_header {
      name  = "Host"
      value = var.domain_name
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases = [var.domain_name]

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.wordpress_cert.arn
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
    Name = "WordPressCFD"
  }
}

resource "aws_acm_certificate" "wordpress_cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  tags = {
    Name = "WordPressCert"
  }
}

resource "aws_route53_record" "wordpress_record" {
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
    Name = "WordPressZone"
  }
}

# S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-static-assets"
  acl    = "private"

  tags = {
    Name = "WordPressBucket"
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

output "wordpress_elb_dns_name" {
  value = aws_lb.wordpress_elb.dns_name
}

output "wordpress_bucket_name" {
  value = aws_s3_bucket.wordpress_bucket.bucket
}

output "wordpress_db_instance_address" {
  value = aws_db_instance.wordpress_db.address
}

output "wordpress_db_instance_port" {
  value = aws_db_instance.wordpress_db.port
}

output "wordpress_db_instance_username" {
  value = aws_db_instance.wordpress_db.username
}

output "wordpress_db_instance_password" {
  value = aws_db_instance.wordpress_db.password
  sensitive = true
}
