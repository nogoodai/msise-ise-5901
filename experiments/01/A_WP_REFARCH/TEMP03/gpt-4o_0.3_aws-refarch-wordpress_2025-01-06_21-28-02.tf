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
  description = "The AWS region to deploy resources in"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
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
  description = "List of IPs allowed to SSH into instances"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "instance_type" {
  description = "EC2 instance type for WordPress"
  default     = "t2.micro"
}

variable "db_instance_class" {
  description = "RDS instance class"
  default     = "db.t2.small"
}

variable "db_username" {
  description = "Database username"
  default     = "admin"
}

variable "db_password" {
  description = "Database password"
  default     = "password"
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
    Name = "WordPressIGW"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = element(var.public_subnet_cidrs, count.index)
  map_public_ip_on_launch = true
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "PublicSubnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "PrivateSubnet-${count.index + 1}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
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
    Name = "DatabaseSG"
  }
}

resource "aws_instance" "bastion" {
  ami           = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 AMI
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public[0].id
  key_name      = "bastion-key"
  security_groups = [aws_security_group.web_sg.name]
  associate_public_ip_address = true
  tags = {
    Name = "BastionHost"
  }
}

resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion.id
}

resource "aws_efs_file_system" "wordpress_efs" {
  tags = {
    Name = "WordPressEFS"
  }
}

resource "aws_efs_mount_target" "wordpress_efs_mt" {
  count          = length(aws_subnet.private)
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_elasticache_subnet_group" "wordpress_cache_subnet_group" {
  name       = "wordpress-cache-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_elasticache_cluster" "wordpress_cache" {
  cluster_id           = "wordpress-cache"
  engine               = "redis"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  subnet_group_name    = aws_elasticache_subnet_group.wordpress_cache_subnet_group.name
  security_group_ids   = [aws_security_group.web_sg.id]
  parameter_group_name = "default.redis3.2"
  tags = {
    Name = "WordPressCache"
  }
}

resource "aws_lb" "wordpress_alb" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = aws_subnet.public[*].id
  tags = {
    Name = "WordPressALB"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.ssl_certificate_arn
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
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
  tags = {
    Name = "WordPressTargetGroup"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  desired_capacity     = 2
  max_size             = 5
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.private[*].id
  launch_configuration = aws_launch_configuration.wordpress_lc.id
  target_group_arns    = [aws_lb_target_group.wordpress_tg.arn]
  tags = [{
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-launch-config"
  image_id      = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 AMI
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_sg.id]
  user_data      = file("wordpress-install.sh")
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.wordpress_instance_profile.name
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role" "wordpress_instance_role" {
  name = "wordpress-instance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_instance_profile" "wordpress_instance_profile" {
  name = "wordpress-instance-profile"
  role = aws_iam_role.wordpress_instance_role.name
}

resource "aws_iam_role_policy" "wordpress_policy" {
  name = "wordpress-policy"
  role = aws_iam_role.wordpress_instance_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:*",
          "efs:*"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_db_instance" "wordpress_db" {
  identifier              = "wordpress-db"
  engine                  = "mysql"
  instance_class          = var.db_instance_class
  allocated_storage       = 20
  name                    = "wordpressdb"
  username                = var.db_username
  password                = var.db_password
  vpc_security_group_ids  = [aws_security_group.db_sg.id]
  multi_az                = true
  skip_final_snapshot     = true
  publicly_accessible     = false
  tags = {
    Name = "WordPressDB"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${random_id.bucket_id.hex}"
  acl    = "private"
  tags = {
    Name = "WordPressAssets"
  }
}

resource "random_id" "bucket_id" {
  byte_length = 8
}

resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "wordpress-s3-origin"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_cache_behavior {
    target_origin_id = "wordpress-s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
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

resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress_alb_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "wordpress"
  type    = "A"
  alias {
    name                   = aws_lb.wordpress_alb.dns_name
    zone_id                = aws_lb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "alb_dns_name" {
  value = aws_lb.wordpress_alb.dns_name
}

output "db_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cdn.domain_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_assets.bucket
}
