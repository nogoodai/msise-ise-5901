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
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "allowed_ssh_ips" {
  description = "IP addresses allowed to SSH into instances"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPress-IGW"
  }
}

resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "PublicSubnet-${count.index}"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "PrivateSubnet-${count.index}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Allow HTTP, HTTPS, and SSH"
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_ips
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

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Allow MySQL from web server"
  ingress {
    description = "MySQL"
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
    Name = "DatabaseSG"
  }
}

resource "aws_instance" "bastion" {
  ami               = data.aws_ami.amazon_linux.id
  instance_type     = "t2.micro"
  key_name          = aws_key_pair.bastion_key.key_name
  subnet_id         = aws_subnet.public[0].id
  associate_public_ip_address = true
  security_groups   = [aws_security_group.web_sg.name]
  tags = {
    Name = "BastionHost"
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
  lifecycle_policy {
    transition_to_ia = "AFTER_7_DAYS"
  }
  tags = {
    Name = "WordPressEFS"
  }
}

resource "aws_efs_mount_target" "wordpress_efs_mount" {
  count          = length(aws_subnet.private)
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_cloudwatch_metric_alarm" "efs_throughput" {
  alarm_name          = "EFSThroughputAlarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Sum"
  threshold           = 1000000
  alarm_actions       = []
  dimensions = {
    FileSystemId = aws_efs_file_system.wordpress_efs.id
  }
}

resource "aws_elb" "wordpress_alb" {
  name               = "wordpress-alb"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.web_sg.id]
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
  }
  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  tags = {
    Name = "WordPressALB"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  launch_configuration = aws_launch_configuration.wordpress_launch_config.id
  vpc_zone_identifier  = aws_subnet.private[*].id
  min_size             = 1
  max_size             = 3
  desired_capacity     = 1
  tags = [
    {
      key                 = "Name"
      value               = "WordPressASG"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_launch_config" {
  image_id          = data.aws_ami.amazon_linux.id
  instance_type     = "t2.micro"
  security_groups   = [aws_security_group.web_sg.id]
  user_data         = file("wordpress-install.sh")
  iam_instance_profile = aws_iam_instance_profile.wordpress_profile.name
}

resource "aws_iam_instance_profile" "wordpress_profile" {
  name = "WordPressInstanceProfile"
  role = aws_iam_role.wordpress_role.name
}

resource "aws_iam_role" "wordpress_role" {
  name = "WordPressRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "wordpress_policy" {
  name = "WordPressPolicy"
  role = aws_iam_role.wordpress_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "elasticfilesystem:ClientMount"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_rds_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  instance_class       = "db.t2.small"
  name                 = "wordpressdb"
  username             = "admin"
  password             = "securepassword" # Use secrets manager in production
  publicly_accessible  = false
  multi_az             = true
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  skip_final_snapshot  = true
  tags = {
    Name = "WordPressRDS"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-static-assets-${random_id.bucket_suffix.hex}"
  acl    = "private"
  versioning {
    enabled = true
  }
  tags = {
    Name = "WordPressAssets"
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 8
}

resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "S3-WordPressAssets"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-WordPressAssets"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "redirect-to-https"
  }
  tags = {
    Name = "WordPressCDN"
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "www"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

data "aws_availability_zones" "available" {}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-*"]
  }
}

output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "rds_endpoint" {
  value = aws_rds_instance.wordpress_db.endpoint
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.wordpress_cdn.domain_name
}
