terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.3.0"
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

variable "subnet_cidrs" {
  type = map(string)
  default = {
    public_subnet_1  = "10.0.1.0/24"
    public_subnet_2  = "10.0.2.0/24"
    private_subnet_1 = "10.0.3.0/24"
    private_subnet_2 = "10.0.4.0/24"
  }
}

variable "ssh_key_name" {
  default = "my-key-pair"
}

variable "allowed_ssh_ips" {
  type = list(string)
  default = ["0.0.0.0/0"]
}

variable "wordpress_instance_type" {
  default = "t2.micro"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "wordpress-vpc"
  }
}

resource "aws_subnet" "public_subnet_1" {
  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = var.subnet_cidrs["public_subnet_1"]
  availability_zone = "${var.region}a"
  map_public_ip_on_launch = true
  tags = {
    Name = "wordpress-public-subnet-1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = var.subnet_cidrs["public_subnet_2"]
  availability_zone = "${var.region}b"
  map_public_ip_on_launch = true
  tags = {
    Name = "wordpress-public-subnet-2"
  }
}

resource "aws_subnet" "private_subnet_1" {
  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = var.subnet_cidrs["private_subnet_1"]
  availability_zone = "${var.region}a"
  tags = {
    Name = "wordpress-private-subnet-1"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = var.subnet_cidrs["private_subnet_2"]
  availability_zone = "${var.region}b"
  tags = {
    Name = "wordpress-private-subnet-2"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "wordpress-igw"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "wordpress-public-rt"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

resource "aws_route_table_association" "public_subnet_1_assoc" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_2_assoc" {
  subnet_id      = aws_subnet.public_subnet_2.id
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
    Name = "wordpress-web-sg"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id

  ingress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress-db-sg"
  }
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnet_1.id
  key_name      = var.ssh_key_name

  vpc_security_group_ids = [
    aws_security_group.web_sg.id
  ]

  associate_public_ip_address = true

  tags = {
    Name = "wordpress-bastion"
  }
}

data "aws_ami" "amazon_linux" {
  owners = ["amazon"]

  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion.id
  tags = {
    Name = "wordpress-bastion-eip"
  }
}

resource "aws_efs_file_system" "efs" {
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  performance_mode = "generalPurpose"
  tags = {
    Name = "wordpress-efs"
  }
}

resource "aws_efs_mount_target" "mt1" {
  file_system_id = aws_efs_file_system.efs.id
  subnet_id      = aws_subnet.private_subnet_1.id
  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_efs_mount_target" "mt2" {
  file_system_id = aws_efs_file_system.efs.id
  subnet_id      = aws_subnet.private_subnet_2.id
  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_elasticache_subnet_group" "elasticache" {
  name       = "wordpress-elasticache-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
  tags = {
    Name = "wordpress-elasticache-subnet-group"
  }
}

resource "aws_elasticache_cluster" "redis_cluster" {
  cluster_id = "wordpress-cache"
  engine     = "redis"
  node_type  = "cache.t2.micro"
  num_cache_nodes = 1

  parameter_group_name = "default.redis3.2"

  subnet_group_name = aws_elasticache_subnet_group.elasticache.name

  tags = {
    Name = "wordpress-cache"
  }
}

resource "aws_lb" "wordpress_alb" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]

  tags = {
    Name = "wordpress-alb"
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

resource "aws_lb_target_group" "wordpress_tg" {
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    interval            = 30
    path                = "/"
    timeout             = 5
    unhealthy_threshold = 5
    healthy_threshold   = 3
    matcher             = "200"
  }

  tags = {
    Name = "wordpress-tg"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  desired_capacity     = 2
  min_size             = 1
  max_size             = 3
  vpc_zone_identifier  = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
  launch_configuration = aws_launch_configuration.wordpress_lc.id
  target_group_arns    = [aws_lb_target_group.wordpress_tg.arn]

  tags = [
    {
      key                 = "Name"
      value               = "wordpress-asg"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-launch-configuration"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.wordpress_instance_type
  key_name      = var.ssh_key_name

  security_groups = [aws_security_group.web_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd php php-mysql
              service httpd start
              chkconfig httpd on
              groupadd www
              usermod -a -G www ec2-user
              chown -R root:www /var/www
              chmod 2775 /var/www
              find /var/www -type d -exec chmod 2775 {} \;
              find /var/www -type f -exec chmod 0664 {} \;
              EOF

  tags = {
    Name = "wordpress-launch-config"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "wordpress-db" {
  identifier = "wordpress-db"
  engine     = "mysql"
  instance_class = "db.t2.small"
  allocated_storage = 20
  name       = "wordpressdb"
  username   = "admin"
  password   = "yourpassword"
  security_groups = [aws_security_group.db_sg.id]
  multi_az   = true
  tags = {
    Name = "wordpress-db"
  }
}

resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_s3_bucket.wordpress_bucket.bucket_regional_domain_name
    origin_id   = "wordpress-s3-origin"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CDN for WordPress assets"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-s3-origin"

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

  tags = {
    Name = "wordpress-cf"
  }
}

resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-static-assets"

  tags = {
    Name = "wordpress-static-assets"
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress_dns" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "www.example.com"
  type    = "A"

  alias {
    name                   = aws_lb.wordpress_alb.dns_name
    zone_id                = aws_lb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

output "wordpress_db_endpoint" {
  value = aws_db_instance.wordpress-db.endpoint
}

output "wordpress_alb_address" {
  value = aws_lb.wordpress_alb.dns_name
}

output "wordpress_s3_bucket" {
  value = aws_s3_bucket.wordpress_bucket.bucket
}

output "wordpress_cf_url" {
  value = aws_cloudfront_distribution.wordpress_cf.domain_name
}

output "route53_zone_name" {
  value = aws_route53_zone.wordpress_zone.name
}
