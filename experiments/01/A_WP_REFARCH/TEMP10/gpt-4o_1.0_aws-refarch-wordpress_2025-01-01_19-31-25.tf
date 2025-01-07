terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
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

resource "aws_subnet" "public_subnet" {
  count = length(var.public_subnet_cidrs)
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "PublicSubnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnet" {
  count = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = var.private_subnet_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "PrivateSubnet-${count.index + 1}"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route" "public_route" {
  route_table_id = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_route_table_assoc" {
  count = length(aws_subnet.public_subnet)
  subnet_id = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
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

data "aws_ami" "latest" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.latest.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnet[0].id
  key_name      = aws_key_pair.deployer.key_name
  security_groups = [aws_security_group.bastion_sg.name]

  tags = {
    Name = "BastionHost"
  }
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = var.ssh_public_key
}

resource "aws_security_group" "bastion_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
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

variable "ssh_public_key" {
  description = "SSH public key for bastion host"
}

variable "admin_cidr" {
  description = "CIDR block for admin access"
}

resource "aws_efs_file_system" "wordpress_efs" {
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  performance_mode = "generalPurpose"
  tags = {
    Name = "WordPressEFS"
  }
}

resource "aws_efs_mount_target" "public" {
  count = length(aws_subnet.private_subnet)
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = aws_subnet.private_subnet[count.index].id
  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_cloudwatch_metric_alarm" "efs_alarm" {
  alarm_name          = "EFS-Burst-Credit-Balance"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Sum"
  threshold           = 10000
  alarm_actions       = [var.alarm_sns_topic]
  dimensions = {
    FileSystemId = aws_efs_file_system.wordpress_efs.id
  }
}

variable "alarm_sns_topic" {
  description = "SNS topic ARN for CloudWatch alarms"
}

resource "aws_elasticache_cluster" "wordpress_cache" {
  engine           = "redis"
  node_type        = "cache.t2.micro"
  num_cache_nodes  = 1
  parameter_group_name = "default.redis3.2"
  subnet_group_name    = aws_elasticache_subnet_group.wordpress_cache.id
  tags = {
    Name = "WordPressCache"
  }
}

resource "aws_elasticache_subnet_group" "wordpress_cache" {
  name       = "wordpress-cache-subnet-group"
  subnet_ids = aws_subnet.private_subnet[*].id
}

resource "aws_lb" "wordpress" {
  name               = "wordpress-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = aws_subnet.public_subnet[*].id

  tags = {
    Name = "WordPressLoadBalancer"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Default 404"
      status_code  = "404"
    }
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.private_subnet[*].id
  launch_configuration = aws_launch_configuration.wordpress_lc.id

  tags = [
    {
      key                 = "Name"
      value               = "WordPressInstance"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_lc" {
  image_id          = data.aws_ami.latest.id
  instance_type     = "t2.micro"
  security_groups   = [aws_security_group.web_sg.id]
  user_data         = base64encode(data.template_file.wordpress_setup.rendered)
  associate_public_ip_address = false
}

data "template_file" "wordpress_setup" {
  template = file("${path.module}/wordpress_setup.sh")
}

resource "aws_rds_instance" "wordpress_db" {
  allocated_storage   = 20
  db_subnet_group_name = aws_db_subnet_group.wordpress_db.id
  engine              = "mysql"
  engine_version      = "5.7"
  instance_class      = "db.t2.small"
  name                = "wordpressdb"
  username            = var.db_username
  password            = var.db_password
  skip_final_snapshot = true
  security_group_names = [aws_security_group.db_sg.name]
}

resource "aws_db_subnet_group" "wordpress_db" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private_subnet[*].id
}

variable "db_username" {
  default = "admin"
}

variable "db_password" {
  sensitive = true
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-static-assets"
  acl    = "public-read"
}

resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "S3-Origin"
  }
  enabled = true
  default_cache_behavior {
    target_origin_id = "S3-Origin"
    viewer_protocol_policy = "redirect-to-https"
  }
}

resource "aws_route53_zone" "wordpress" {
  name = var.domain_name
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.wordpress.id
  name    = "www.${var.domain_name}"
  type    = "A"
  alias {
    name                   = aws_lb.wordpress.dns_name
    zone_id                = aws_lb.wordpress.zone_id
    evaluate_target_health = true
  }
}

output "load_balancer_dns_name" {
  value = aws_lb.wordpress.dns_name
}

output "rds_endpoint" {
  value = aws_rds_instance.wordpress_db.endpoint
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.wordpress_cf.domain_name
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}
