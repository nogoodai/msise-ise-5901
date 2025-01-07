terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0.0"
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

variable "public_subnet_cidrs" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "admin_ips" {
  description = "Allowed IPs for SSH access"
  default     = ["0.0.0.0/0"]
}

variable "ami_id" {
  description = "AMI ID for EC2 instances"
  default     = "ami-0abcdef1234567890"
}

variable "instance_type" {
  description = "Instance type for EC2 instances"
  default     = "t2.micro"
}

variable "environment" {
  description = "Deployment environment"
  default     = "production"
}

variable "domain_name" {
  description = "Domain name for Route 53"
  default     = "example.com"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_subnet" "public_subnet" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = element(var.public_subnet_cidrs, count.index)
  map_public_ip_on_launch = true
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "WordPressPublicSubnet-${count.index + 1}"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private_subnet" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "WordPressPrivateSubnet-${count.index + 1}"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name        = "WordPressPublicRT"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_route_table_association" "public_association" {
  count          = length(aws_subnet.public_subnet)
  subnet_id      = element(aws_subnet.public_subnet.*.id, count.index)
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
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_ips
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "WordPressWebSG"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "WordPressDBSG"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_instance" "bastion" {
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = element(aws_subnet.public_subnet.*.id, 0)
  key_name      = aws_key_pair.bastion_key.key_name
  security_groups = [
    aws_security_group.web_sg.id
  ]
  associate_public_ip_address = true
  tags = {
    Name        = "WordPressBastion"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_key_pair" "bastion_key" {
  key_name   = "bastion-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion.id
}

resource "aws_efs_file_system" "wordpress_efs" {
  tags = {
    Name        = "WordPressEFS"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_efs_mount_target" "efs_mount_target" {
  count          = length(aws_subnet.private_subnet)
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = element(aws_subnet.private_subnet.*.id, count.index)
  security_groups = [
    aws_security_group.web_sg.id
  ]
}

resource "aws_rds_instance" "wordpress_rds" {
  allocated_storage      = 20
  engine                 = "mysql"
  instance_class         = "db.t2.small"
  name                   = "wordpress"
  username               = "admin"
  password               = "changeme"
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  multi_az               = true
  tags = {
    Name        = "WordPressRDS"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_elb" "wordpress_elb" {
  availability_zones = data.aws_availability_zones.available.names
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
    ssl_certificate_id = "arn:aws:acm:us-east-1:123456789012:certificate/abcd1234-abcd-1234-abcd-1234abcd1234"
  }
  instances = aws_instance.wordpress_instance.*.id
  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  security_groups = [
    aws_security_group.web_sg.id
  ]
  tags = {
    Name        = "WordPressELB"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  availability_zones = data.aws_availability_zones.available.names
  min_size           = 1
  max_size           = 3
  desired_capacity   = 2
  launch_configuration = aws_launch_configuration.wordpress_launch_config.id
  health_check_type  = "ELB"
  target_group_arns  = [aws_lb_target_group.target_group.arn]
  vpc_zone_identifier = aws_subnet.private_subnet.*.id
  tags = [{
    key                 = "Name"
    value               = "WordPressASG"
    propagate_at_launch = true
  }]
}

resource "aws_launch_configuration" "wordpress_launch_config" {
  image_id          = var.ami_id
  instance_type     = var.instance_type
  security_groups   = [aws_security_group.web_sg.id]
  user_data         = filebase64("wordpress_install_script.sh")
  key_name          = aws_key_pair.bastion_key.key_name
  associate_public_ip_address = true
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${var.environment}"
  acl    = "private"
  tags = {
    Name        = "WordPressAssets"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [var.domain_name]
  viewer_certificate {
    acm_certificate_arn            = "arn:aws:acm:us-east-1:123456789012:certificate/abcd1234-abcd-1234-abcd-1234abcd1234"
    ssl_support_method             = "sni-only"
    minimum_protocol_version = "TLSv1.2_2018"
  }
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-elb"
    viewer_protocol_policy = "redirect-to-https"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }
  tags = {
    Name        = "WordPressDistribution"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_distribution.hosted_zone_id
    evaluate_target_health = true
  }
}

data "aws_availability_zones" "available" {}

output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "cloudfront_distribution_domain" {
  value = aws_cloudfront_distribution.wordpress_distribution.domain_name
}

output "rds_endpoint" {
  value = aws_rds_instance.wordpress_rds.endpoint
}
