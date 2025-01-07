terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-1"
}

variable "project_name" {
  default = "wordpress"
}

variable "admin_ip" {
  description = "The IP address that needs SSH access to the bastion host."
  default     = "0.0.0.0/0"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name       = "${var.project_name}-vpc"
    Environment = "production"
    Project    = var.project_name
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name       = "${var.project_name}-igw"
    Environment = "production"
    Project    = var.project_name
  }
}

resource "aws_subnet" "public_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name       = "${var.project_name}-public-${count.index}"
    Environment = "production"
    Project    = var.project_name
  }
}

resource "aws_subnet" "private_subnet" {
  count             = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.${count.index + 2}.0/24"
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name       = "${var.project_name}-private-${count.index}"
    Environment = "production"
    Project    = var.project_name
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name       = "${var.project_name}-public-rt"
    Environment = "production"
    Project    = var.project_name
  }
}

resource "aws_route_table_association" "public_rta" {
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
    cidr_blocks = [var.admin_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name       = "${var.project_name}-web-sg"
    Environment = "production"
    Project    = var.project_name
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
    Name       = "${var.project_name}-db-sg"
    Environment = "production"
    Project    = var.project_name
  }
}

resource "aws_key_pair" "bastion_key" {
  key_name   = "${var.project_name}-bastion-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "aws_eip" "bastion" {
  vpc = true
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.latest.id
  instance_type = "t2.micro"
  key_name      = aws_key_pair.bastion_key.key_name
  subnet_id     = aws_subnet.public_subnet[0].id

  associate_public_ip_address = true

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  tags = {
    Name       = "${var.project_name}-bastion"
    Environment = "production"
    Project    = var.project_name
  }
}

resource "aws_elastic_ip_association" "bastion" {
  instance_id = aws_instance.bastion.id
  allocation_id = aws_eip.bastion.id
}

resource "aws_efs_file_system" "wordpress_efs" {
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name       = "${var.project_name}-efs"
    Environment = "production"
    Project    = var.project_name
  }
}

resource "aws_efs_mount_target" "efs_mount_target" {
  count          = length(aws_subnet.private_subnet)
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = element(aws_subnet.private_subnet.*.id, count.index)
  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_db_instance" "wordpress_rds" {
  engine            = "mysql"
  instance_class    = "db.t2.small"
  allocated_storage = 20
  db_name           = "wordpress"
  username          = "admin"
  password          = "password123"
  multi_az          = true
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  skip_final_snapshot = true

  tags = {
    Name       = "${var.project_name}-rds"
    Environment = "production"
    Project    = var.project_name
  }
}

resource "aws_lb" "app_lb" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = aws_subnet.public_subnet[*].id

  enable_deletion_protection = false

  tags = {
    Name       = "${var.project_name}-alb"
    Environment = "production"
    Project    = var.project_name
  }
}

resource "aws_lb_target_group" "wordpress_tg" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    unhealthy_threshold = 2
    healthy_threshold   = 2
    protocol            = "HTTP"
  }

  tags = {
    Name       = "${var.project_name}-tg"
    Environment = "production"
    Project    = var.project_name
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  launch_configuration = aws_launch_configuration.wordpress_lc.id
  vpc_zone_identifier = aws_subnet.private_subnet[*].id
  min_size            = 2
  max_size            = 5
  desired_capacity    = 2
  health_check_type   = "EC2"

  target_group_arns = [aws_lb_target_group.wordpress_tg.arn]

  tags = [
    { key = "Name", value = "${var.project_name}-asg", propagate_at_launch = true },
    { key = "Environment", value = "production", propagate_at_launch = true },
    { key = "Project", value = var.project_name, propagate_at_launch = true }
  ]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "${var.project_name}-lc"
  image_id      = data.aws_ami.latest.id
  instance_type = "t2.micro"
  key_name      = aws_key_pair.bastion_key.key_name

  user_data = <<-EOF
                #!/bin/bash
                yum update -y
                amazon-linux-extras install php7.4 -y
                yum install -y httpd wordpress php-mysql
                systemctl start httpd
                systemctl enable httpd
                EOF

  security_groups = [aws_security_group.web_sg.id]
}

data "aws_ami" "latest" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "${var.project_name}-assets"

  tags = {
    Name       = "${var.project_name}-assets"
    Environment = "production"
    Project    = var.project_name
  }

  lifecycle_rule {
    enabled = true
    noncurrent_version_expiration {
      days = 30
    }
  }
}

resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_lb.app_lb.dns_name
    origin_id   = "WordPressALB"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
    }
  }

  enabled = true
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WordPressALB"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  aliases = ["www.example.com"]

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name       = "${var.project_name}-cf"
    Environment = "production"
    Project    = var.project_name
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"

  tags = {
    Name       = "${var.project_name}-zone"
    Environment = "production"
    Project    = var.project_name
  }
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "www"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cf.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cf.hosted_zone_id
    evaluate_target_health = false
  }
}

output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "alb_dns" {
  value = aws_lb.app_lb.dns_name
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cf.domain_name
}
