terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-1"
}

variable "vpc_cidr_block" {
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "key_name" {
  description = "Name of the SSH key pair"
}

variable "admin_ip" {
  description = "IP range allowed to access via SSH"
}

variable "wordpress_ami" {
  description = "AMI ID for WordPress EC2 instances"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr_block

  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name = "WordPressIGW"
  }
}

resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name = "WordPressPublicSubnet-${count.index}"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name = "WordPressPrivateSubnet-${count.index}"
  }
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
    cidr_blocks = [var.admin_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WordPressWebSG"
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
    Name = "WordPressDBSG"
  }
}

resource "aws_instance" "bastion" {
  ami           = var.wordpress_ami
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnets[0].id
  key_name      = var.key_name
  associate_public_ip_address = true

  tags = {
    Name = "WordPressBastion"
  }

  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion.id
}

resource "aws_efs_file_system" "wordpress_efs" {
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name = "WordPressEFS"
  }
}

resource "aws_efs_mount_target" "efs_mount" {
  count          = length(aws_subnet.private_subnets)
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = aws_subnet.private_subnets[count.index].id
  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_db_instance" "rds_instance" {
  allocated_storage    = 20
  engine               = "mysql"
  instance_class       = "db.t2.small"
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password"
  multi_az             = true
  publicly_accessible  = false
  skip_final_snapshot  = true

  vpc_security_group_ids = [aws_security_group.db_sg.id]

  tags = {
    Name = "WordPressDB"
  }
}

resource "aws_elb" "wordpress_elb" {
  name               = "wordpress-alb"
  security_groups    = [aws_security_group.web_sg.id]
  availability_zones = data.aws_availability_zones.available.names

  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "WordPressELB"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  launch_configuration = aws_launch_configuration.wordpress_launch_configuration.id
  min_size             = 1
  max_size             = 3
  vpc_zone_identifier  = aws_subnet.private_subnets.*.id

  tag {
    key                 = "Name"
    value               = "WordPressASG"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name          = "wordpress-launch-config"
  image_id      = var.wordpress_ami
  instance_type = "t2.micro"
  key_name      = var.key_name

  user_data = data.template_file.wordpress_user_data.rendered

  security_groups = [aws_security_group.web_sg.id]

  lifecycle {
    create_before_destroy = true
  }
}

data "template_file" "wordpress_user_data" {
  template = file("wordpress_user_data.tpl")
}

resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-origin"
  }

  enabled             = true
  default_cache_behavior {
    allowed_methods    = ["GET", "HEAD", "OPTIONS"]
    cached_methods     = ["GET", "HEAD"]
    target_origin_id   = "wordpress-origin"
    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "WordPressCDN"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-bucket-${random_id.bucket_id.hex}"

  tags = {
    Name = "WordPressAssets"
  }
}

resource "random_id" "bucket_id" {
  byte_length = 8
}

resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"

  tags = {
    Name = "WordPressZone"
  }
}

resource "aws_route53_record" "wordpress_a_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "www"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cdn.hosted_zone_id
    evaluate_target_health = true
  }
}

output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "bastion_public_ip" {
  value = aws_eip.bastion_eip.public_ip
}

output "rds_endpoint" {
  value = aws_db_instance.rds_instance.endpoint
}

output "load_balancer_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "cloudfront_url" {
  value = aws_cloudfront_distribution.wordpress_cdn.domain_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_assets.bucket
}
