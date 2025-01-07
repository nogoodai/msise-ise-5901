provider "aws" {
  region = "us-west-2"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-west-2a", "us-west-2b"]
}

variable "ami_id" {
  type    = string
  default = "ami-abcd1234"
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

variable "wordpress_admin_ips" {
  type    = list(string)
  default = ["192.168.1.100/32"]
}

variable "rds_instance_class" {
  type    = string
  default = "db.t2.small"
}

variable "rds_engine" {
  type    = string
  default = "mysql"
}

variable "elasticache_node_type" {
  type    = string
  default = "cache.t2.micro"
}

variable "elasticache_engine" {
  type    = string
  default = "memcached"
}

variable "cloudfront_distribution_domain" {
  type    = string
  default = "example.com"
}

variable "route53_zone_name" {
  type    = string
  default = "example.com"
}

variable "ec2_instance_count" {
  type    = number
  default = 2
}

# VPC configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

# Subnet configuration
resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnet_cidrs)

  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
}

resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
}

# Internet gateway configuration
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
}

# Route table configuration
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }

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

# Associate route tables with subnets
resource "aws_route_table_association" "public_route_table_associations" {
  count = length(aws_subnet.public_subnets)

  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_route_table_associations" {
  count = length(aws_subnet.private_subnets)

  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security group configuration
resource "aws_security_group" "web_server_sg" {
  name        = "web-server-sg"
  description = "Security group for web server instances"
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
    cidr_blocks = var.wordpress_admin_ips
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Security group for RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "elb_sg" {
  name        = "elb-sg"
  description = "Security group for ELB"
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
}

# EC2 instance configuration
resource "aws_instance" "wordpress_instances" {
  count = var.ec2_instance_count

  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public_subnets[count.index].id
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  key_name        = "wordpress-ec2-key"

  tags = {
    Name = "WordPressInstance-${count.index}"
  }
}

# RDS instance configuration
resource "aws_db_instance" "wordpress_db" {
  identifier           = "wordpress-db"
  engine               = var.rds_engine
  instance_class       = var.rds_instance_class
  allocated_storage     = 20
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.rds_subnet_group.name
  multi_az             = true
  storage_type         = "gp2"
  username             = "wordpress"
  password             = "wordpress"
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = [aws_subnet.private_subnets[0].id, aws_subnet.private_subnets[1].id]
}

# Elastic Load Balancer configuration
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = [aws_subnet.public_subnets[0].id, aws_subnet.public_subnets[1].id]
  security_groups = [aws_security_group.elb_sg.id]

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
    ssl_certificate_id = "arn:aws:iam::123456789012:server-certificate/wordpress-ssl-cert"
  }
}

# Auto Scaling Group configuration
resource "aws_autoscaling_group" "wordpress_asg" {
  name                 = "wordpress-asg"
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  min_size             = 1
  max_size             = 5
  health_check_type    = "ELB"
  vpc_zone_identifier  = [aws_subnet.public_subnets[0].id, aws_subnet.public_subnets[1].id]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_server_sg.id]
  key_name        = "wordpress-ec2-key"
}

# CloudFront distribution configuration
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }

  enabled = true

  default_root_object = "index.html"

  aliases             = [var.cloudfront_distribution_domain]
  ssl_certificate_id = "arn:aws:iam::123456789012:server-certificate/wordpress-ssl-cert"

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

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
}

# S3 bucket configuration
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket        = "wordpress-static-assets"
  force_destroy = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource = "arn:aws:s3:::wordpress-static-assets/*"
      },
    ]
  })
}

# Route 53 configuration
resource "aws_route53_zone" "wordpress_zone" {
  name = var.route53_zone_name
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.route53_zone_name
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "wordpress_cloudfront_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.route53_zone_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_distribution.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_distribution.zone_id
    evaluate_target_health = true
  }
}
