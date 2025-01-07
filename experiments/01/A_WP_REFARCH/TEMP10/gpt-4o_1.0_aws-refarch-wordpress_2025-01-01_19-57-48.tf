terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-1"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnets_cidr" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets_cidr" {
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "allowed_ssh_ips" {
  description = "List of IPs allowed for SSH access"
  default     = ["0.0.0.0/0"]
}

variable "admin_ips" {
  default = ["0.0.0.0/0"]
}

variable "db_instance_class" {
  default = "db.t2.small"
}

variable "ec2_instance_type" {
  default = "t2.micro"
}

variable "wordpress_disk_size" {
  default = 30
}

variable "asg_max_size" {
  default = 3
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "wordpress-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "wordpress-igw"
  }
}

resource "aws_subnet" "public_subnet" {
  count             = length(var.public_subnets_cidr)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.public_subnets_cidr, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name = "wordpress-public-subnet-${count.index}"
  }
}

resource "aws_subnet" "private_subnet" {
  count             = length(var.private_subnets_cidr)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.private_subnets_cidr, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "wordpress-private-subnet-${count.index}"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "wordpress-public-rt"
  }
}

resource "aws_route_table_association" "public_rta" {
  count = length(aws_subnet.public_subnet)
  subnet_id = element(aws_subnet.public_subnet.*.id, count.index)
  route_table_id = aws_route_table.public_rt.id
}

data "aws_availability_zones" "available" {}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.main.id

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
    from_port    = 22
    to_port      = 22
    protocol     = "tcp"
    cidr_blocks  = var.allowed_ssh_ips
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress-web-sg"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
    security_groups  = [aws_security_group.web_sg.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress-db-sg"
  }
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.latest.id
  instance_type = var.ec2_instance_type
  subnet_id     = element(aws_subnet.public_subnet.*.id, 0)
  associate_public_ip_address = true
  key_name      = var.key_pair_name
  security_groups = [aws_security_group.web_sg.id]

  tags = {
    Name = "wordpress-bastion"
  }
}

resource "aws_eip" "bastion_ip" {
  vpc      = true
  instance = aws_instance.bastion.id
}

data "aws_ami" "latest" {
  owners      = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_efs_file_system" "wordpress" {
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name = "wordpress-efs"
  }
}

resource "aws_efs_mount_target" "wordpress" {
  count          = length(aws_subnet.private_subnet)
  file_system_id = aws_efs_file_system.wordpress.id
  subnet_id      = element(aws_subnet.private_subnet.*.id, count.index)
  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_cloudwatch_metric_alarm" "efs_alarm" {
  alarm_name          = "wordpress-efs-burst-credit-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 5
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Average"
  threshold           = 1000000

  dimensions = {
    FileSystemId = aws_efs_file_system.wordpress.id
  }
}

resource "aws_elb" "wordpress_elb" {
  name               = "wordpress-elb"
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
    ssl_certificate_id = aws_acm_certificate.domain_validated.arn
  }

  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_acm_certificate" "domain_validated" {
  domain_name       = "example.com"
  validation_method = "DNS"
}

resource "aws_autoscaling_group" "wordpress_asg" {
  desired_capacity     = 2
  max_size             = var.asg_max_size
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.private_subnet.*.id
  launch_configuration = aws_launch_configuration.wordpress_lc.id
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-launch-config"
  image_id      = data.aws_ami.latest.id
  instance_type = var.ec2_instance_type
  user_data     = filebase64("wordpress-install.sh")

  security_groups = [aws_security_group.web_sg.id]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = var.db_instance_class
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password"
  parameter_group_name = "default.mysql5.7"

  multi_az            = true
  vpc_security_group_ids = [aws_security_group.db_sg.id]
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-bucket"

  acl    = "public-read"

  tags = {
    Name = "wordpress-assets"
  }
}

resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_domain_name
    origin_id   = "S3-wordpress-assets"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.s3_access.iam_arn
    }
  }

  enabled = true

  default_cache_behavior {
    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    target_origin_id = "S3-wordpress-assets"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.domain_validated.arn
    ssl_support_method  = "sni-only"
  }

  tags = {
    Name = "wordpress-cloudfront"
  }
}

resource "aws_cloudfront_origin_access_identity" "s3_access" {
  comment = "Access identity for wordpress assets S3 bucket"
}

resource "aws_route53_zone" "main" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "wordpress"
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id                = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = true
  }
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "db_instance_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cdn.domain_name
}
