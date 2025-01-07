terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy the infrastructure"
  type        = string
  default     = "us-west-2"
}

variable "project" {
  description = "The name of the project"
  type        = string
  default     = "wordpress"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  enable_dns_support  = true
  enable_dns_hostnames = true
  tags = {
    Name        = "${var.project}-vpc"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "${var.project}-igw"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name        = "${var.project}-public-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  map_public_ip_on_launch = false
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name        = "${var.project}-private-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "${var.project}-public-rt"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public_subnet" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_server" {
  vpc_id = aws_vpc.main.id
  description = "Allow HTTP, HTTPS, and SSH access"
  
  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = ["1.2.3.4/32"]  # Replace with allowed IPs for SSH
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project}-web-sg"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group" "database" {
  vpc_id = aws_vpc.main.id
  description = "Allow MySQL access from web servers"
  
  ingress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
    security_groups = [aws_security_group.web_server.id]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project}-db-sg"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group" "elb" {
  vpc_id = aws_vpc.main.id
  description = "Allow HTTP and HTTPS access for ELB"
  
  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project}-elb-sg"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_elb" "wordpress" {
  name               = "${var.project}-elb"
  availability_zones = data.aws_availability_zones.available.names
  security_groups    = [aws_security_group.elb.id]
  instances          = []  # Populated by Auto Scaling

  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  listener {
    instance_port     = 443
    instance_protocol = "HTTPS"
    lb_port           = 443
    lb_protocol       = "HTTPS"
    ssl_certificate_id = data.aws_acm_certificate.word_press.arn
  }

  tags = {
    Name        = "${var.project}-elb"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_autoscaling_group" "wordpress" {
  desired_capacity     = 2
  max_size             = 5
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.private[*].id
  launch_configuration = aws_launch_configuration.wordpress.id
  health_check_type    = "ELB"
  health_check_grace_period = 300
  load_balancers       = [aws_elb.wordpress.name]
  
  tags = [
    {
      key                 = "Name"
      value               = "${var.project}-wordpress"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = var.environment
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = var.project
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress" {
  name          = "${var.project}-wordpress-lc"
  image_id      = data.aws_ami.wordpress.id  # Specify the correct AMI
  instance_type = "t3.micro"
  security_groups = [aws_security_group.web_server.id]
  user_data     = file("wordpress-install.sh")

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "wordpress" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t2.micro"
  name                 = var.db_name
  username             = var.db_username
  password             = var.db_password
  parameter_group_name = "default.mysql8.0"
  vpc_security_group_ids = [aws_security_group.database.id]
  multi_az             = true
  skip_final_snapshot  = true

  tags = {
    Name        = "${var.project}-db"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_s3_bucket.static.bucket_region
    origin_id   = "S3-${aws_s3_bucket.static.id}"
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.static.id}"

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400

    forward_headers = ["*"]
  }

  price_class = "PriceClass_All"
  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "DE"]
    }
  }

  viewer_certificate {
    acm_certificate_arn = data.aws_acm_certificate.word_press.arn
    ssl_support_method  = "sni-only"
  }

  tags = {
    Name        = "${var.project}-cdn"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_s3_bucket" "static" {
  bucket = "${var.project}-static-assets"
  acl    = "public-read"

  tags = {
    Name        = "${var.project}-static-assets"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route53_zone" "primary" {
  name = var.domain_name
  tags = {
    Name        = "${var.project}-zone"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.primary.id
  name    = "www"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress.hosted_zone_id
    evaluate_target_health = false
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "wordpress" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

data "aws_acm_certificate" "word_press" {
  domain   = "www.${var.domain_name}"
  statuses = ["ISSUED"]
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "elb_dns_name" {
  description = "DNS name of the ELB"
  value       = aws_elb.wordpress.dns_name
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.wordpress.domain_name
}

output "db_instance_endpoint" {
  description = "RDS DB instance endpoint"
  value       = aws_db_instance.wordpress.endpoint
}
