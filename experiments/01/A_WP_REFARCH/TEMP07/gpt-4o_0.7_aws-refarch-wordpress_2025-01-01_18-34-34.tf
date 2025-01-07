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
  description = "The AWS region to deploy resources in."
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "The CIDR blocks for the public subnets."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "The CIDR blocks for the private subnets."
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "allowed_ssh_ips" {
  description = "The list of IPs allowed to SSH into the bastion host."
  default     = ["0.0.0.0/0"]
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "WordPressPublicSubnet-${count.index + 1}"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "WordPressPrivateSubnet-${count.index + 1}"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name        = "WordPressPublicRouteTable"
    Environment = "production"
    Project     = "WordPress"
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
    Name        = "WordPressWebSG"
    Environment = "production"
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
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_instance" "bastion" {
  ami           = "ami-12345678"  # Replace with actual AMI
  instance_type = "t2.micro"
  key_name      = var.key_name
  subnet_id     = aws_subnet.public[0].id
  associate_public_ip_address = true
  security_groups = [aws_security_group.web_sg.id]
  tags = {
    Name        = "WordPressBastion"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion.id
}

resource "aws_efs_file_system" "wordpress" {
  tags = {
    Name        = "WordPressEFS"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_efs_mount_target" "wordpress" {
  count      = length(aws_subnet.private)
  file_system_id = aws_efs_file_system.wordpress.id
  subnet_id  = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_elasticache_subnet_group" "wordpress" {
  name       = "wordpress-elasticache-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_elasticache_cluster" "wordpress" {
  cluster_id           = "wordpress-cache"
  engine               = "memcached"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 2
  parameter_group_name = "default.memcached1.4"
  subnet_group_name    = aws_elasticache_subnet_group.wordpress.name
  tags = {
    Name        = "WordPressElastiCache"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_lb" "wordpress" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = aws_subnet.public[*].id
  tags = {
    Name        = "WordPressALB"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_lb_target_group" "wordpress" {
  name     = "wordpress-targets"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
  tags = {
    Name        = "WordPressTargetGroup"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}

resource "aws_autoscaling_group" "wordpress" {
  availability_zones   = data.aws_availability_zones.available.names
  desired_capacity     = 2
  max_size             = 4
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.private[*].id
  launch_configuration = aws_launch_configuration.wordpress.name
  target_group_arns    = [aws_lb_target_group.wordpress.arn]
  tags = [
    {
      key                 = "Name"
      value               = "WordPressInstance"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress" {
  name          = "wordpress-launch-configuration"
  image_id      = "ami-12345678"  # Replace with actual AMI
  instance_type = "t2.micro"
  security_groups = [aws_security_group.web_sg.id]
  user_data      = file("wordpress-install.sh")
  key_name       = var.key_name
}

resource "aws_rds_instance" "wordpress" {
  identifier             = "wordpress-db"
  engine                 = "mysql"
  instance_class         = "db.t2.small"
  allocated_storage      = 20
  db_subnet_group_name   = aws_db_subnet_group.wordpress.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  multi_az               = true
  tags = {
    Name        = "WordPressRDS"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_db_subnet_group" "wordpress" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-bucket"
  acl    = "private"
  tags = {
    Name        = "WordPressAssetsBucket"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "S3-WordPressAssets"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront for WordPress"
  default_root_object = "index.html"

  default_cache_behavior {
    target_origin_id = "S3-WordPressAssets"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  tags = {
    Name        = "WordPressCloudFront"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_route53_zone" "wordpress" {
  name = "example.com"  # Replace with the actual domain.
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = "www"
  type    = "A"
  alias {
    name                   = aws_lb.wordpress.dns_name
    zone_id                = aws_lb.wordpress.zone_id
    evaluate_target_health = true
  }
}

output "vpc_id" {
  description = "The ID of the VPC."
  value       = aws_vpc.wordpress_vpc.id
}

output "alb_dns_name" {
  description = "The DNS name of the ALB."
  value       = aws_lb.wordpress.dns_name
}

output "db_endpoint" {
  description = "The endpoint of the RDS database."
  value       = aws_rds_instance.wordpress.endpoint
}

output "cloudfront_domain_name" {
  description = "The domain name of the CloudFront distribution."
  value       = aws_cloudfront_distribution.wordpress.domain_name
}
