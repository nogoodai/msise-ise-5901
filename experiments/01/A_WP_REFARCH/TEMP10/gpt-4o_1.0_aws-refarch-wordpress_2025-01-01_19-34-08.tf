terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  default = "us-east-1"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "wordpress-vpc"
    Environment = var.environment
    Project = var.project_name
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "wordpress-igw"
  }
}

resource "aws_subnet" "public" {
  count = 2
  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index)
  map_public_ip_on_launch = true
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name = "wordpress-public-subnet-${count.index}"
  }
}
      
resource "aws_subnet" "private" {
  count = 2
  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index + 2)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name = "wordpress-private-subnet-${count.index}"
  }
}
      
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "wordpress-public-rt"
  }
}

resource "aws_route_table_association" "public_rt_assoc" {
  count          = 2
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id

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
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = [var.admin_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress-web-sg"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress-db-sg"
  }
}

resource "aws_instance" "bastion" {
  ami = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  
  subnet_id = element(aws_subnet.public.*.id, 0)
  security_groups = [aws_security_group.web_sg.name]

  key_name = var.ssh_key_name

  associate_public_ip_address = true

  tags = {
    Name = "wordpress-bastion-host"
  }
}

resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  instance_class       = "db.t2.small"
  name                 = "wordpressdb"
  username             = "admin"
  password             = var.db_password
  multi_az             = true
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  db_subnet_group_name = aws_db_subnet_group.word_press.id

  tags = {
    Name = "wordpress-db"
  }
}

resource "aws_db_subnet_group" "word_press" {
  name        = "wordpress-db-subnet-group"
  subnet_ids  = aws_subnet.private.*.id

  tags = {
    Name = "wordpress-db-subnet-group"
  }
}

resource "aws_lb" "wordpress_alb" {
  name = "wordpress-alb"
  internal = false
  security_groups = [aws_security_group.web_sg.id]
  subnets = aws_subnet.public.*.id

  tags = {
    Name = "wordpress-alb"
  }
}

resource "aws_lb_listener" "listener_http" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port     = 80
  protocol = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

resource "aws_lb_listener" "listener_https" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port     = 443
  protocol = "HTTPS"
  ssl_policy = "ELBSecurityPolicy-2016-08"
  certificate_arn = var.ssl_certificate_arn

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

resource "aws_lb_target_group" "wordpress_tg" {
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    path                = "/healthcheck"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
    matcher             = "200-399"
  }

  tags = {
    Name = "wordpress-tg"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  launch_configuration = aws_launch_configuration.wordpress_launch_config.id
  min_size             = 2
  max_size             = 5
  desired_capacity     = 2
  vpc_zone_identifier  = aws_subnet.public.*.id
  load_balancer_names  = [aws_lb.wordpress_alb.name]

  tags = [
    {
      key                 = "Name"
      value               = "wordpress-asg"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_launch_config" {
  name = "wordpress-launch-configuration"
  image_id = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  security_groups = [aws_security_group.web_sg.id]
  associate_public_ip_address = true
  user_data = file("path/to/wordpress_installation_script.sh")
  key_name = var.ssh_key_name

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "${var.project_name}-wordpress-assets"
  acl    = "public-read"

  tags = {
    Name = "wordpress-assets"
  }
}

data "aws_iam_policy_document" "s3_bucket_policy" {
  statement {
    sid     = "PublicReadForGetBucketObjects"
    effect  = "Allow"
    actions = ["s3:GetObject"]

    resources = ["${aws_s3_bucket.wordpress_bucket.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
  }
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.wordpress_bucket.id
  policy = data.aws_iam_policy_document.s3_bucket_policy.json
}

resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_s3_bucket.wordpress_bucket.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.wordpress_bucket.id
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.wordpress_bucket.id

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_All"
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "wordpress-cloudfront"
  }
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = data.aws_route53_zone.wordpress_zone.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.wordpress_alb.dns_name
    zone_id                = aws_lb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

data "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
}

output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "public_subnets" {
  value = aws_subnet.public.*.id
}

output "private_subnets" {
  value = aws_subnet.private.*.id
}

output "database_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}

output "alb_dns_name" {
  value = aws_lb.wordpress_alb.dns_name
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.wordpress_cdn.id
}

variable "environment" {
  default = "production"
}

variable "project_name" {
  default = "wordpress-project"
}

variable "admin_cidr_block" {
  description = "CIDR block for admin access"
  type        = string
}

variable "ssh_key_name" {
  description = "SSH key name"
  type        = string
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "ssl_certificate_arn" {
  description = "SSL Certificate ARN for ALB"
  type        = string
}

variable "domain_name" {
  description = "Domain name for Route 53"
  type        = string
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}
