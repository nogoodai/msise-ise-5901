provider "aws" {
  region = "us-west-2"
  version = "5.1.0"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
}

variable "database_instance_class" {
  type        = string
  default     = "db.t2.micro"
}

variable "database_username" {
  type        = string
  default     = "wordpressuser"
}

variable "database_password" {
  type        = string
  sensitive   = true
}

variable "domain_name" {
  type        = string
  default     = "example.com"
}

variable "cloudfront_ssl_certificate_arn" {
  type        = string
  default     = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
}

# Networking
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
  }
}

resource "aws_route_table" "wordpress_public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name        = "WordPressPublicRT"
    Environment = "production"
  }
}

resource "aws_subnet" "wordpress_public_subnets" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name        = "WordPressPublicSubnet${count.index + 1}"
    Environment = "production"
  }
}

resource "aws_route_table_association" "wordpress_public_rt_assoc" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.wordpress_public_subnets[count.index].id
  route_table_id = aws_route_table.wordpress_public_rt.id
}

# Security Groups
resource "aws_security_group" "wordpress_web_sg" {
  name        = "WordPressWebSG"
  description = "Allow inbound HTTP/HTTPS and SSH traffic"
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
    Name        = "WordPressWebSG"
    Environment = "production"
  }
}

resource "aws_security_group" "wordpress_db_sg" {
  name        = "WordPressDBSG"
  description = "Allow inbound MySQL traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_web_sg.id]
  }
  tags = {
    Name        = "WordPressDBSG"
    Environment = "production"
  }
}

# RDS Instance
resource "aws_db_instance" "wordpress_db" {
  identifier           = "wordpress-db"
  instance_class       = var.database_instance_class
  engine               = "mysql"
  engine_version       = "8.0.20"
  username             = var.database_username
  password             = var.database_password
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.wordpress_db_sg.id]
  skip_final_snapshot  = true
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.wordpress_public_subnets[*].id
}

# EC2 Instances
resource "aws_instance" "wordpress_web" {
  count         = 2
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_web_sg.id]
  subnet_id = aws_subnet.wordpress_public_subnets[count.index].id
  key_name               = "wordpress"
  tags = {
    Name        = "WordPressWeb${count.index + 1}"
    Environment = "production"
  }
}

# Elastic Load Balancer
resource "aws_alb" "wordpress_alb" {
  name            = "wordpress-alb"
  subnets         = aws_subnet.wordpress_public_subnets[*].id
  security_groups = [aws_security_group.wordpress_web_sg.id]
  tags = {
    Name        = "WordPressALB"
    Environment = "production"
  }
}

resource "aws_alb_target_group" "wordpress_alb_tg" {
  name     = "wordpress-alb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressALBTG"
    Environment = "production"
  }
}

resource "aws_alb_listener" "wordpress_alb_listener" {
  load_balancer_arn = aws_alb.wordpress_alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    target_group_arn = aws_alb_target_group.wordpress_alb_tg.arn
    type             = "forward"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  max_size                  = 5
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = aws_subnet.wordpress_public_subnets[*].id
  target_group_arns         = [aws_alb_target_group.wordpress_alb_tg.arn]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.wordpress_web_sg.id]
  key_name               = "wordpress"
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = "wordpress-alb"
  }
  enabled         = true
  is_ipv6_enabled = true
  aliases         = [var.domain_name]
  default_root_object = "index.html"
  viewer_certificate {
    acm_certificate_arn = var.cloudfront_ssl_certificate_arn
    ssl_support_method  = "sni-only"
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  tags = {
    Name        = "WordPressCFD"
    Environment = "production"
  }
}

# S3 Bucket
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = var.domain_name
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
          aws_s3_bucket.wordpress_s3_bucket.arn,
          "${aws_s3_bucket.wordpress_s3_bucket.arn}/*",
        ]
      },
    ]
  })
  tags = {
    Name        = "WordPressS3Bucket"
    Environment = "production"
  }
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress_r53_zone" {
  name = var.domain_name
}

resource "aws_route53_record" "wordpress_r53_record" {
  zone_id = aws_route53_zone.wordpress_r53_zone.id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_alb.wordpress_alb.dns_name
    zone_id               = aws_alb.wordpress_alb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "wordpress_cfd_r53_record" {
  zone_id = aws_route53_zone.wordpress_r53_zone.id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cfd.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cfd.zone_id
    evaluate_target_health = false
  }
}

output "alb_dns_name" {
  value = aws_alb.wordpress_alb.dns_name
}

output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cfd.domain_name
}

output "r53_zone_id" {
  value = aws_route53_zone.wordpress_r53_zone.id
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3_bucket.id
}
