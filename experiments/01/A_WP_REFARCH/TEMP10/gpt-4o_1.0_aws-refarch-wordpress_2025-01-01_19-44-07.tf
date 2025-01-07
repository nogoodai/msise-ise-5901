terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy resources into"
  default     = "us-east-1"
}

variable "admin_ip" {
  description = "The IP address for administrative SSH access"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "A list of CIDR blocks for the public subnets"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "A list of CIDR blocks for the private subnets"
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "instance_type" {
  description = "The instance type for EC2 WordPress instances"
  default     = "t3.micro"
}

variable "rds_instance_class" {
  description = "The instance class for the RDS database"
  default     = "db.t2.small"
}

variable "ami_id" {
  description = "The AMI ID for the EC2 instances"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "wordpress-vpc"
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "internet-gateway"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "public-subnet-${count.index}"
  }
}

resource "aws_subnet" "private" {
  count                   = length(var.private_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  map_public_ip_on_launch = false
  availability_zone       = element(data.aws_availability_zones.available.names, count.index + 2)
  tags = {
    Name = "private-subnet-${count.index}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }
  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_server_sg" {
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
    Name = "web-server-sg"
  }
}

resource "aws_security_group" "database_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "database-sg"
  }
}

resource "aws_instance" "bastion" {
  ami           = var.ami_id
  instance_type = "t2.micro"
  key_name      = var.key_name
  subnet_id     = aws_subnet.public[0].id

  vpc_security_group_ids = [aws_security_group.web_server_sg.id]

  tags = {
    Name = "bastion-host"
  }
  associate_public_ip_address = true
}

resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
}

resource "aws_efs_file_system" "efs" {
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  tags = {
    Name = "wordpress-efs"
  }
}

resource "aws_efs_mount_target" "efs_mount" {
  count          = length(var.private_subnet_cidrs)
  file_system_id = aws_efs_file_system.efs.id
  subnet_id      = aws_subnet.private[count.index].id
  security_groups = [
    aws_security_group.web_server_sg.id
  ]
}

resource "aws_elasticache_subnet_group" "subnet_group" {
  name       = "elasticache-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_elasticache_cluster" "elasticache" {
  cluster_id           = "wordpress-cache-cluster"
  engine               = "memcached"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 2
  subnet_group_name    = aws_elasticache_subnet_group.subnet_group.name
  tags = {
    Name = "elasticache-cluster"
  }
}

resource "aws_elb" "web_server_elb" {
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
    ssl_certificate_id = "arn:aws:acm:us-east-1:123456789012:certificate/EXAMPLE-certificate"
  }

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "web-server-elb"
  }
}

resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name                        = "wordpress-launch-configuration"
  image_id                    = var.ami_id
  instance_type               = var.instance_type
  security_groups             = [aws_security_group.web_server_sg.id]
  user_data                   = file("wordpress_user_data.sh")
  key_name                    = var.key_name
  associate_public_ip_address = false
}

resource "aws_autoscaling_group" "wordpress_asg" {
  launch_configuration     = aws_launch_configuration.wordpress_launch_configuration.name
  min_size                 = 1
  max_size                 = 3
  vpc_zone_identifier      = aws_subnet.private[*].id
  target_group_arns = [aws_elb.web_server_elb.arn]

  tag {
    key                 = "Name"
    value               = "wordpress-instance"
    propagate_at_launch = true
  }
}

resource "aws_db_instance" "wordpress_rds" {
  identifier        = "wordpress-db"
  engine            = "mysql"
  instance_class    = var.rds_instance_class
  allocated_storage = 20
  db_name           = "wordpress"
  username          = "admin"
  password          = var.db_password
  multi_az          = true
  vpc_security_group_ids = [aws_security_group.database_sg.id]
  skip_final_snapshot    = true
  tags = {
    Name = "wordpress-rds"
  }
}

resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-static-assets-${random_id.bucket_id.hex}"
  acl    = "public-read"

  tags = {
    Name = "wordpress-static-assets"
  }
}

resource "random_id" "bucket_id" {
  byte_length = 6
}

resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_s3_bucket.wordpress_bucket.bucket_regional_domain_name
    origin_id   = "wordpress-s3"
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-s3"

    forwarded_values {
      query_string = false
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  price_class         = "PriceClass_100"
  viewer_certificate {
    cloudfront_default_certificate = true
  }
  tags = {
    Name = "wordpress-distribution"
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
}

resource "aws_route53_record" "wordpress_alias" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_cloudwatch_dashboard" "wordpress_dashboard" {
  dashboard_name = "wordpress_dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric",
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.wordpress_instance.id],
          ],
          period = 300,
          stat   = "Average",
          region = var.region
        }
      }
    ]
  })
}

output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "elb_dns_name" {
  value = aws_elb.web_server_elb.dns_name
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_distribution.domain_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_bucket.id
}

data "aws_availability_zones" "available" {}

variable "db_password" {
  description = "The password for the RDS instance"
}
