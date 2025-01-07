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
  description = "The AWS region to deploy resources in."
  default     = "us-east-1"
}

variable "public_key" {
  description = "SSH public key for bastion host access."
}

variable "allowed_ssh_ip" {
  description = "IP range allowed for SSH access to bastion host."
  default     = "0.0.0.0/0"
}

variable "db_username" {
  description = "Username for the RDS MySQL database."
}

variable "db_password" {
  description = "Password for the RDS MySQL database."
  sensitive   = true
}

variable "db_name" {
  description = "Database name for WordPress."
  default     = "wordpress_db"
}

variable "efs_transition_days" {
  description = "Days before transitioning files to infrequent access in EFS."
  default     = 30
}

variable "project_name" {
  description = "The name of the project resources."
  default     = "wordpress"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = element(["10.0.1.0/24", "10.0.2.0/24"], count.index)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name        = "${var.project_name}-public-subnet-${count.index + 1}"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_subnet" "private" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = element(["10.0.3.0/24", "10.0.4.0/24"], count.index)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = false
  tags = {
    Name        = "${var.project_name}-private-subnet-${count.index + 1}"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "${var.project_name}-igw"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_server_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    description = "Allow HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow SSH traffic"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name        = "${var.project_name}-web-sg"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    description = "Allow MySQL traffic from web servers"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-db-sg"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_instance" "bastion" {
  ami                    = "ami-12345678" # specify your AMI
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public[0].id
  key_name               = var.public_key
  associate_public_ip_address = true

  vpc_security_group_ids = [aws_security_group.web_server_sg.id]

  tags = {
    Name        = "${var.project_name}-bastion"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
}

resource "aws_efs_file_system" "main" {
  tags = {
    Name        = "${var.project_name}-efs"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_efs_mount_target" "mount" {
  count          = 2
  file_system_id = aws_efs_file_system.main.id
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  security_groups = [aws_security_group.web_server_sg.id]
}

resource "aws_cloudwatch_metric_alarm" "efs_throughput" {
  alarm_name          = "${var.project_name}-efs-throughput-alert"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Average"
  threshold           = 10000000
  actions_enabled     = true

  dimensions = {
    FileSystemId = aws_efs_file_system.main.id
  }
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.project_name}-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "${var.project_name}-elasticache"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_elasticache_cluster" "main" {
  cluster_id          = "${var.project_name}-cache"
  engine              = "redis"
  node_type           = "cache.t2.micro"
  num_cache_nodes     = 1
  parameter_group_name = "default.redis3.2"
  subnet_group_name   = aws_elasticache_subnet_group.main.name
  security_group_ids  = [aws_security_group.web_server_sg.id]

  tags = {
    Name        = "${var.project_name}-cache"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_alb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_server_sg.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name        = "${var.project_name}-alb"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_alb_target_group" "main" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "${var.project_name}-tg"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_alb_listener" "http" {
  load_balancer_arn = aws_alb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.main.arn
  }
}

resource "aws_db_instance" "main" {
  identifier              = "${var.project_name}-rds-db"
  allocated_storage       = 20
  engine                  = "mysql"
  engine_version          = "5.7"
  instance_class          = "db.t2.small"
  name                    = var.db_name
  username                = var.db_username
  password                = var.db_password
  multi_az                = true
  publicly_accessible     = false
  vpc_security_group_ids  = [aws_security_group.db_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.main.id

  tags = {
    Name        = "${var.project_name}-rds-db"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "${var.project_name}-db-subnet"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_autoscaling_group" "main" {
  desired_capacity     = 2
  max_size             = 4
  min_size             = 2
  availability_zones   = data.aws_availability_zones.available.names
  vpc_zone_identifier  = aws_subnet.public[*].id
  target_group_arns    = [aws_alb_target_group.main.arn]

  launch_configuration = aws_launch_configuration.main.name

  tags = [
    {
      key                 = "Name"
      value               = "${var.project_name}-web-asg"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "main" {
  name          = "${var.project_name}-launch-config"
  image_id      = "ami-12345678" # specify your AMI
  instance_type = "t2.micro"
  key_name      = var.public_key

  security_groups = [aws_security_group.web_server_sg.id]

  user_data = <<-EOF
    #!/bin/bash
    yum install -y httpd php php-mysql
    service httpd start
    chkconfig httpd on
    cd /var/www/html
    wget https://wordpress.org/latest.tar.gz
    tar -xzf latest.tar.gz
    cp -r wordpress/* .
    rm -rf wordpress latest.tar.gz
    EOF
}

resource "aws_cloudfront_distribution" "main" {
  origin {
    domain_name = aws_s3_bucket.assets.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.assets.id}"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront Distribution for WordPress"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.assets.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 3600 
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name        = "${var.project_name}-cloudfront"
    Environment = "production"
    Project     = var.project_name
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "aws_s3_bucket" "assets" {
  bucket = "${var.project_name}-assets"

  tags = {
    Name        = "${var.project_name}-assets"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_route53_zone" "main" {
  name = "example.com"

  tags = {
    Name        = "${var.project_name}-route53-zone"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www"
  type    = "A"
  
  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

output "alb_dns" {
  description = "DNS name of the ALB"
  value       = aws_alb.main.dns_name
}

output "rds_endpoint" {
  description = "The RDS instance endpoint"
  value       = aws_db_instance.main.endpoint
}

output "cloudfront_domain_name" {
  description = "CloudFront Distribution Domain Name"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "s3_bucket_name" {
  description = "S3 bucket for static assets"
  value       = aws_s3_bucket.assets.id
}

output "route53_zone_id" {
  description = "Route 53 Zone ID"
  value       = aws_route53_zone.main.zone_id
}
