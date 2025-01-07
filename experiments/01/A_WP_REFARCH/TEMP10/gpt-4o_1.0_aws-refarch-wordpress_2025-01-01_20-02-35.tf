terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  backend "s3" {}
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy resources into"
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "The CIDR blocks for the public subnets"
  default     = ["10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "The CIDR blocks for the private subnets"
  default     = ["10.0.2.0/24"]
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
    Name = "wordpress-igw"
  }
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = element(var.public_subnet_cidrs, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "wordpress-public-subnet-${count.index}"
  }
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = element(var.private_subnet_cidrs, count.index)

  tags = {
    Name = "wordpress-private-subnet-${count.index}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "wordpress-public-route-table"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name = "wordpress-private-route-table"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "web_server_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id

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
    cidr_blocks = ["203.0.113.0/24"]  # Replace with your allowed IP range
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress-web-server-sg"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id

  ingress {
    description = "Allow MySQL traffic from web server"
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
    Name = "wordpress-db-sg"
  }
}

resource "aws_instance" "bastion" {
  ami           = "ami-0c55b159cbfafe1f0"  # Replace with a valid AMI ID in your region
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public[0].id

  associate_public_ip_address = true

  key_name = "your-key-pair"  # Replace with your key pair name

  security_groups = [aws_security_group.web_server_sg.id]

  tags = {
    Name = "wordpress-bastion"
  }
}

resource "aws_efs_file_system" "wordpress_efs" {
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name = "wordpress-efs-filesystem"
  }
}

resource "aws_efs_mount_target" "efs_mount" {
  count      = length(var.private_subnet_cidrs)
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id     = aws_subnet.private[count.index].id

  security_groups = [aws_security_group.web_server_sg.id]
}

resource "aws_rds_instance" "wordpress_db" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t2.small"
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password"  # Replace with a secure password
  skip_final_snapshot  = true
  multi_az             = true

  vpc_security_group_ids = [aws_security_group.db_sg.id]

  tags = {
    Name = "wordpress-db-instance"
  }
}

resource "aws_elasticache_cluster" "wordpress_cache" {
  cluster_id           = "wordpress-cache"
  engine               = "memcached"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 2

  subnet_group_name    = aws_elasticache_subnet_group.wordpress_cache_subnet_group.name

  tags = {
    Name = "wordpress-cache-cluster"
  }
}

resource "aws_elasticache_subnet_group" "wordpress_cache_subnet_group" {
  name       = "wordpress-cache-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_elb" "wordpress_alb" {
  name               = "wordpress-alb"
  availability_zones = [for az in data.aws_availability_zones.available.names : az]

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
    ssl_certificate_id = "arn:aws:acm:region:account-id:certificate/certificate-id"
  }

  tags = {
    Name = "wordpress-alb"
  }
}

data "aws_availability_zones" "available" {}

resource "aws_launch_configuration" "web" {
  name_prefix           = "wordpress-web"
  image_id              = "ami-0c55b159cbfafe1f0"  # Replace with a valid AMI ID
  instance_type         = "t2.micro"
  security_groups       = [aws_security_group.web_server_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install -y php7.4
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "web_asg" {
  launch_configuration = aws_launch_configuration.web.name
  min_size             = 1
  max_size             = 3
  desired_capacity     = 2

  vpc_zone_identifier  = aws_subnet.public[*].id

  tags = [
    {
      key                 = "Name"
      value               = "wordpress-asg-instance"
      propagate_at_launch = true
    }
  ]
}

resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_elb.wordpress_alb.dns_name
    origin_id   = "wordpress"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "match-viewer"
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "WordPress CloudFront Distribution"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress"

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

  price_class = "PriceClass_100"

  tags = {
    Name = "wordpress-cloudfront-cdn"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-bucket"

  acl = "private"

  tags = {
    Name = "wordpress-assets"
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"  # Replace with your domain name

  tags = {
    Name = "wordpress-route53-zone"
  }
}

resource "aws_route53_record" "root" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "www"
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_alb.dns_name
    zone_id                = aws_elb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

output "wordpress_vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "elb_dns_name" {
  value = aws_elb.wordpress_alb.dns_name
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cdn.domain_name
}

output "rds_endpoint" {
  value = aws_rds_instance.wordpress_db.endpoint
}
