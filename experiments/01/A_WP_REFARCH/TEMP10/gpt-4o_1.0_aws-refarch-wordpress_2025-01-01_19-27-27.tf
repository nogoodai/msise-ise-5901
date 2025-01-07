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
  default     = "us-west-2"
}

variable "vpc_cidr_block" {
  description = "The CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr_blocks" {
  description = "The CIDR blocks for the public subnets."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidr_blocks" {
  description = "The CIDR blocks for the private subnets."
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "admin_ip" {
  description = "IP range that needs SSH access."
  default     = "0.0.0.0/0"
}

variable "bastion_instance_type" {
  description = "EC2 instance type for Bastion host."
  default     = "t2.micro"
}

variable "wordpress_instance_type" {
  description = "EC2 instance type for WordPress."
  default     = "t2.micro"
}

variable "rds_instance_class" {
  description = "RDS instance class."
  default     = "db.t2.small"
}

variable "key_pair_name" {
  description = "The name of the key pair to use for SSH access to EC2 instances."
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name = "wordpress-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "wordpress-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidr_blocks)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr_blocks[count.index]
  map_public_ip_on_launch = true
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name = "wordpress-public-subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidr_blocks)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr_blocks[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name = "wordpress-private-subnet-${count.index + 1}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "wordpress-public-route-table"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  name        = "wordpress-web-sg"
  vpc_id      = aws_vpc.main.id

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
    Name = "wordpress-web-sg"
  }
}

resource "aws_security_group" "bastion_sg" {
  name        = "wordpress-bastion-sg"
  vpc_id      = aws_vpc.main.id

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
    Name = "wordpress-bastion-sg"
  }
}

resource "aws_key_pair" "bastion_key" {
  key_name   = var.key_pair_name
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.bastion_instance_type
  subnet_id     = element(aws_subnet.public.*.id, 0)
  key_name      = aws_key_pair.bastion_key.id
  associate_public_ip_address = true

  tags = {
    Name = "wordpress-bastion"
  }

  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
}

resource "aws_rds_instance" "wordpress_db" {
  engine            = "mysql"
  instance_class    = var.rds_instance_class
  allocated_storage = 20
  db_name           = "wordpress"
  username          = "admin"
  password          = "admin123"

  vpc_security_group_ids = [aws_security_group.web_sg.id]
  multi_az               = true

  tags = {
    Name = "wordpress-rds"
  }
}

resource "aws_elb" "wordpress_elb" {
  name               = "wordpress-elb"
  availability_zones = data.aws_availability_zones.available.names

  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  instances = concat(aws_instance.wordpress.*.id)

  tags = {
    Name = "wordpress-elb"
  }
}

resource "aws_auto_scaling_group" "wordpress_asg" {
  desired_capacity     = 1
  max_size             = 3
  min_size             = 1

  vpc_zone_identifier  = aws_subnet.private[*].id

  launch_configuration = aws_launch_configuration.wordpress_lc.id

  tags = [
    {
      key                 = "Name"
      value               = "wordpress-asg"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_lc" {
  image_id        = data.aws_ami.amazon_linux.id
  instance_type   = var.wordpress_instance_type
  security_groups = [aws_security_group.web_sg.id]
  key_name        = var.key_pair_name

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd php php-mysql amazon-linux-extras
              amazon-linux-extras enable php7.4
              yum clean metadata
              systemctl start httpd
              systemctl enable httpd
              # Add WordPress configuration here
              EOF
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-bucket-${random_id.bucket_id.hex}"
  acl    = "private"

  tags = {
    Name = "wordpress-assets"
  }
}

resource "random_id" "bucket_id" {
  byte_length = 8
}

resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "s3-origin"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.wordpress_oai.cloudfront_access_identity_path
    }
  }

  enabled = true

  default_cache_behavior {
    target_origin_id       = "s3-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD"]
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

  price_class = "PriceClass_All"

  tags = {
    Name = "wordpress-cf"
  }
}

resource "aws_route53_zone" "main_zone" {
  name = "example.com"

  tags = {
    Name = "wordpress-zone"
  }
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.main_zone.zone_id
  name    = "www.example.com"
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id                = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = true
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

data "aws_availability_zones" "available" {}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "rds_endpoint" {
  value = aws_rds_instance.wordpress_db.endpoint
}

output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cf.domain_name
}

output "s3_bucket_url" {
  value = aws_s3_bucket.wordpress_assets.bucket_domain_name
}
