provider "aws" {
  region = "us-west-2"
}

variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "public_subnets_cidr_block" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnets_cidr_block" {
  type        = list(string)
  default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

variable "db_instance_class" {
  type        = string
  default     = "db.t2.small"
}

variable "ec2_instance_type" {
  type        = string
  default     = "t2.micro"
}

variable "instance_count" {
  type        = number
  default     = 2
}

variable "domain_name" {
  type        = string
}

# VPC and networking resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_subnet" "public_subnets" {
  count             = length(var.availability_zones)
  cidr_block        = var.public_subnets_cidr_block[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PublicSubnet${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.availability_zones)
  cidr_block        = var.private_subnets_cidr_block[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PrivateSubnet${count.index + 1}"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

resource "aws_route_table_association" "public_route_table_association" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_route_table_association" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security groups
resource "aws_security_group" "wordpress_sg" {
  name        = "WordPressSG"
  description = "Security group for WordPress instances"
  vpc_id      = aws_vpc.wordpress_vpc.id
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
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "WordPressSG"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "RDSSG"
  description = "Security group for RDS instances"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "RDSSG"
  }
}

# RDS instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 10
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = var.db_instance_class
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password123"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = "default-vpc-0a96a77122343512"
  maintainence_window     = "Mon:00:00-Mon:03:00"
  availability_zone = var.availability_zones[0]
  storage_type = "gp2"
  backup_retention_period = 30
  skip_final_snapshot  = true
}

# Elastic Load Balancer
resource "aws_alb" "wordpress_alb" {
  name               = "WordPressALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.wordpress_sg.id]
  subnets            = aws_subnet.public_subnets.*.id
  tags = {
    Name = "WordPressALB"
  }
}

# Target group
resource "aws_alb_target_group" "wordpress_tg" {
  name     = "WordPressTG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressTG"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                 = "WordPressASG"
  max_size             = 5
  min_size             = var.instance_count
  health_check_grace_period = 300
  health_check_type = "EC2"
  force_delete         = true
  vpc_zone_identifier = aws_subnet.private_subnets.*.id
  target_group_arns = aws_alb_target_group.wordpress_tg.arn

}

resource "aws_instance" "wordpress_instance" {
  count          = var.instance_count
  ami           = "ami-0c2ab3b8efb09f272"
  instance_type = var.ec2_instance_type
  subnet_id     = aws_subnet.private_subnets[count.index].id
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  user_data     = file("${path.module}/ubuntu-wordpress")
  tags = {
    Name = "WordPressInstance${count.index + 1}"
  }
}

# S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = var.domain_name
  acl    = "private"
  force_destroy = true
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_s3_bucket.wordpress_bucket.bucket_regional_domain_name
    origin_id   = "S3Origin"
  }
  enabled = true
  is_ipv6_enabled = true
  default_root_object = "index.html"
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/404.html"
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_zone" {
  name    = var.domain_name
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_alb.wordpress_alb.dns_name
    zone_id               = aws_alb.wordpress_alb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_ec2_instance" "bastion" {
  ami           = "ami-0c2ab3b8efb09f272"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnets[0].id
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
}

resource "aws_efs_file_system" "wordpress_efs" {
  tags = {
    Name = "WordPressEFS"
  }
}

resource "aws_efs_mount_target" "wordpress_mount_target" {
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = aws_subnet.private_subnets[0].id
}

resource "aws_cloudwatch_metric_alarm" "wordpress_efs_alarm" {
  alarm_name                = "WordPressEFSSpaceAlarm"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = "2"
  metric_name               = "FreeInodes"
  namespace                 = "AWS/EFS"
  period                    = "300"
  statistic                 = "Average"
  threshold                 = "1000000"
  alarm_description         = "Alarm for EFS space usage"
  insufficient_data_actions = []
  alarm_actions             = []
  dimensions = {
    FileSystemId = aws_efs_file_system.wordpress_efs.id
  }
}

resource "aws_elasticache_cluster" "wordpress_cache" {
  cluster_id           = "wordpress-cache"
  engine               = "memcached"
  node_type            = "cache.t2.micro"
  num_cache_nodes       = 1
  parameter_group_name = "default.memcached1.4"
  port                 = 11211
  availability_zone    = var.availability_zones[0]
  security_group_ids = [aws_security_group.wordpress_sg.id]
  tags = {
    Name = "WordPressCache"
  }
}

output "wordpress_alb_dns_name" {
  value = aws_alb.wordpress_alb.dns_name
}

output "wordpress_rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_bucket.bucket
}

output "wordpress_cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.wordpress_distribution.id
}
