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
  description = "AWS region to deploy the resources"
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
  description = "List of IPs allowed to SSH into the bastion host"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "key_name" {
  description = "Name of the SSH key"
  type        = string
}

variable "certificate_arn" {
  description = "ARN of the SSL certificate for ALB"
  type        = string
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "wordpress-igw"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = element(var.public_subnet_cidrs, count.index)
  map_public_ip_on_launch = false
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "wordpress-public-subnet-${count.index + 1}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "wordpress-private-subnet-${count.index + 1}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

data "aws_availability_zones" "available" {}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name        = "wordpress-public-route-table"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_server_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Security group for WordPress web server"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP traffic"
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS traffic"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  tags = {
    Name        = "wordpress-web-server-sg"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "database_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Security group for WordPress database"
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
    description     = "Allow MySQL traffic from web server"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  tags = {
    Name        = "wordpress-database-sg"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public[0].id
  associate_public_ip_address = false
  key_name      = var.key_name
  monitoring    = true
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  tags = {
    Name        = "bastion-host"
    Environment = "Production"
    Project     = "WordPress"
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  tags = {
    Name        = "bastion-eip"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_efs_file_system" "wordpress_efs" {
  encrypted = true
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  performance_mode = "generalPurpose"
  tags = {
    Name        = "wordpress-efs"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_efs_mount_target" "wordpress_efs_mount" {
  count          = length(aws_subnet.private)
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.web_server_sg.id]
}

resource "aws_elasticache_cluster" "wordpress_cache" {
  cluster_id           = "wordpress-cache-cluster"
  engine               = "redis"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis3.2"
  subnet_group_name    = aws_elasticache_subnet_group.wordpress_cache_subnet_group.name
  port                 = 6379
  tags = {
    Name        = "wordpress-cache-cluster"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_elasticache_subnet_group" "wordpress_cache_subnet_group" {
  name       = "wordpress-cache-subnet-group"
  subnet_ids = aws_subnet.private[*].id
  tags = {
    Name        = "wordpress-cache-subnet-group"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_alb" "wordpress_alb" {
  name            = "wordpress-alb"
  load_balancer_type = "application"
  security_groups = [aws_security_group.web_server_sg.id]
  subnets         = aws_subnet.public[*].id
  enable_deletion_protection = true
  drop_invalid_header_fields = true
  tags = {
    Name        = "wordpress-alb"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_alb_listener" "http" {
  load_balancer_arn = aws_alb.wordpress_alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      protocol = "HTTPS"
      port     = "443"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_alb_listener" "https" {
  load_balancer_arn = aws_alb.wordpress_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.certificate_arn
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "HTTPS"
      status_code  = "200"
    }
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.private[*].id
  launch_configuration = aws_launch_configuration.wordpress_launch_config.id
  load_balancers       = [aws_alb.wordpress_alb.arn]
  tags = [
    {
      key                 = "Name"
      value               = "wordpress-ec2"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_launch_config" {
  image_id          = data.aws_ami.amazon_linux.id
  instance_type     = "t2.micro"
  security_groups   = [aws_security_group.web_server_sg.id]
  user_data         = file("wordpress_install.sh")
  key_name          = var.key_name
  associate_public_ip_address = false
}

resource "aws_db_instance" "wordpress_rds" {
  identifier              = "wordpress-db"
  allocated_storage       = 20
  engine                  = "mysql"
  instance_class          = "db.t2.small"
  name                    = "wordpressdb"
  username                = "admin"
  password                = var.db_password
  vpc_security_group_ids  = [aws_security_group.database_sg.id]
  storage_encrypted       = true
  backup_retention_period = 7
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]
  skip_final_snapshot     = true
  multi_az                = true
  publicly_accessible     = false
  tags = {
    Name        = "wordpress-db"
    Environment = "Production"
    Project     = "WordPress"
  }
}

variable "db_password" {
  description = "The password for the RDS instance"
  type        = string
  sensitive   = true
}

resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = "wordpress-alb"
  }
  enabled             = true
  default_root_object = "index.php"
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-alb"
    viewer_protocol_policy = "redirect-to-https"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = false
    minimum_protocol_version       = "TLSv1.2_2019"
  }
  tags = {
    Name        = "wordpress-cdn"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-static-assets"
  acl    = "private"
  versioning {
    enabled = true
  }
  logging {
    target_bucket = "log-bucket"
    target_prefix = "wordpress-assets/"
  }
  tags = {
    Name        = "wordpress-assets"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
  tags = {
    Name        = "example.com"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route53_record" "alb_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "www"
  type    = "A"
  alias {
    name                   = aws_alb.wordpress_alb.dns_name
    zone_id                = aws_alb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "cdn_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "cdn"
  type    = "CNAME"
  ttl     = "300"
  records = [aws_cloudfront_distribution.wordpress_cdn.domain_name]
}

output "vpc_id" {
  value       = aws_vpc.wordpress_vpc.id
  description = "The ID of the VPC"
}

output "alb_dns_name" {
  value       = aws_alb.wordpress_alb.dns_name
  description = "The DNS name of the ALB"
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.wordpress_cdn.domain_name
  description = "The domain name of the CloudFront distribution"
}

output "rds_endpoint" {
  value       = aws_db_instance.wordpress_rds.endpoint
  description = "The endpoint of the RDS instance"
}
