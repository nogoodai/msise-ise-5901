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

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "bastion_ami" {
  default = "ami-0c55b159cbfafe1f0" # Example Amazon Linux 2 AMI
}

variable "bastion_instance_type" {
  default = "t2.micro"
}

variable "wordpress_instance_type" {
  default = "t2.micro"
}

variable "db_instance_class" {
  default = "db.t2.small"
}

variable "db_engine" {
  default = "mysql"
}

variable "auto_scaling_min_size" {
  default = 1
}

variable "auto_scaling_max_size" {
  default = 3
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "WordPressPublicSubnet-${count.index}"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "WordPressPrivateSubnet-${count.index}"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "WordPressIGW"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name = "WordPressPublicRouteTable"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web" {
  name        = "web-sg"
  description = "Allow HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.main.id

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

  tags = {
    Name = "WebServerSG"
  }
}

resource "aws_security_group" "database" {
  name        = "database-sg"
  description = "Allow MySQL access"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "DatabaseSG"
  }
}

resource "aws_security_group" "bastion" {
  name_prefix = "bastion-sg-"
  description = "Allow SSH traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["your.ssh.access.ip/32"] # Replace with your IP address
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "BastionSG"
  }
}

resource "aws_instance" "bastion" {
  ami                  = var.bastion_ami
  instance_type        = var.bastion_instance_type
  subnet_id            = element(aws_subnet.private[*].id, 0)
  associate_public_ip_address = true
  security_groups      = [aws_security_group.bastion.name]

  key_name             = "your-key-pair" # Replace with your SSH key pair name

  tags = {
    Name = "BastionHost"
  }
}

resource "aws_elasticsearch_service_domain" "wordpress" {
  domain_name           = "wordpress-elastic-search"
  elasticsearch_version = "7.10"

  cluster_config {
    instance_type = "t3.small.elasticsearch"
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 10
  }

  vpc_options {
    subnet_ids = aws_subnet.private[*].id
  }

  tags = {
    Name = "WordPressES"
  }
}

resource "aws_efs_file_system" "wordpress" {
  performance_mode = "generalPurpose"
  tags = {
    Name = "WordPressEFS"
  }
}

resource "aws_efs_mount_target" "wordpress" {
  count          = length(aws_subnet.private)
  file_system_id = aws_efs_file_system.wordpress.id
  subnet_id      = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.web.id]
}

resource "aws_cloudwatch_log_group" "efs" {
  name = "/aws/efs/wordpress"
  retention_in_days = 7
}

resource "aws_cloudwatch_metric_alarm" "efs_credit_balance" {
  alarm_name          = "EFSBurstCreditBalanceAlarm"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Average"
  threshold           = 1000000
  alarm_actions       = ["arn:aws:sns:REGION:ACCOUNT_ID:MyTopic"] # Replace REGION, ACCOUNT_ID, and MyTopic with your values

  dimensions = {
    FileSystemId = aws_efs_file_system.wordpress.id
  }
}

resource "aws_auto_scaling_group" "wordpress" {
  desired_capacity     = 1
  max_size             = var.auto_scaling_max_size
  min_size             = var.auto_scaling_min_size
  vpc_zone_identifier  = aws_subnet.private[*].id
  health_check_type    = "EC2"
  launch_configuration = aws_launch_configuration.wordpress.id
  tag {
    key                 = "Name"
    value               = "WordPressASG"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress" {
  name          = "wordpress-launch-configuration"
  image_id      = data.aws_ami.wordpress.id
  instance_type = var.wordpress_instance_type

  security_groups = [aws_security_group.web.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd php php-mysqlnd
              systemctl start httpd
              systemctl enable httpd
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_ami" "wordpress" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_elb" "wordpress" {
  name               = "wordpress-elb"
  availability_zones = data.aws_availability_zones.available.names
  security_groups    = [aws_security_group.web.id]

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
    unhealthy_threshold = 2
    healthy_threshold   = 2
  }

  tags = {
    Name = "WordPressELB"
  }
}

resource "aws_rds_instance" "wordpress" {
  allocated_storage    = 20
  engine               = var.db_engine
  instance_class       = var.db_instance_class
  name                 = "wordpressdb"
  username             = "admin"
  password             = "Password123!" # Replace with a secure password
  vpc_security_group_ids = [aws_security_group.database.id]
  multi_az             = true

  skip_final_snapshot = true

  tags = {
    Name = "WordPressRDS"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-bucket"

  tags = {
    Name = "WordPressAssets"
  }
}

resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "wordpressS3Origin"

    s3_origin_config {
      origin_access_identity = "origin-access-identity/cloudfront/EXAMPLE"
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "WordPress CloudFront Distribution"
  default_cache_behavior {
    allowed_methods    = ["GET", "HEAD"]
    cached_methods     = ["GET", "HEAD"]
    target_origin_id   = "wordpressS3Origin"
    viewer_protocol_policy = "redirect-to-https"
  }

  tags = {
    Name = "WordPressCF"
  }
}

resource "aws_route53_zone" "wordpress" {
  name = "example.com" # Replace with your domain

  tags = {
    Name = "WordPressZone"
  }
}

resource "aws_route53_record" "wordpress" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = "www.example.com" # Replace with your subdomain
  type    = "A"
  alias {
    name                   = aws_elb.wordpress.dns_name
    zone_id                = aws_elb.wordpress.zone_id
    evaluate_target_health = true
  }
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "alb_dns_name" {
  value = aws_elb.wordpress.dns_name
}

output "db_endpoint" {
  value = aws_rds_instance.wordpress.endpoint
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress.domain_name
}

data "aws_availability_zones" "available" {}
