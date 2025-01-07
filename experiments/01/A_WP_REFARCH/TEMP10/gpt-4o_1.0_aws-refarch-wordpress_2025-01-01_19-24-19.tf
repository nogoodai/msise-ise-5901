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
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project"
  default     = "wordpress"
}

variable "environment" {
  description = "Deployment environment"
  default     = "production"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

resource "aws_vpc" "wordpress" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "wordpress" {
  vpc_id = aws_vpc.wordpress.id
  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name        = "${var.project_name}-public-subnet-${count.index + 1}"
    Environment = var.environment
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "${var.project_name}-private-subnet-${count.index + 1}"
    Environment = var.environment
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress.id
  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = var.environment
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress.id
}

resource "aws_route_table_association" "public_association" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

data "aws_availability_zones" "available" {}

resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  vpc_id      = aws_vpc.wordpress.id
  description = "Security group for web servers"
  tags = {
    Name        = "${var.project_name}-web-sg"
    Environment = var.environment
  }

  ingress {
    description      = "Allow HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    description      = "Allow HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db_sg" {
  name        = "${var.project_name}-db-sg"
  vpc_id      = aws_vpc.wordpress.id
  description = "Security group for database server"
  tags = {
    Name        = "${var.project_name}-db-sg"
    Environment = var.environment
  }

  ingress {
    description     = "Allow MySQL from web server"
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
}

resource "aws_instance" "bastion" {
  ami                         = "ami-12345678"  # Example AMI, change as needed
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public[0].id
  associate_public_ip_address = true
  key_name                    = var.key_pair_name
  security_groups             = [aws_security_group.web_sg.name]

  tags = {
    Name        = "${var.project_name}-bastion"
    Environment = var.environment
  }

  provisioner "remote-exec" {
    inline = [
      "echo Hello, World"
    ]
  }
}

variable "key_pair_name" {
  description = "SSH key pair name for EC2 instances"
}

resource "aws_efs_file_system" "wordpress" {
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  performance_mode = "generalPurpose"
  tags = {
    Name        = "${var.project_name}-efs"
    Environment = var.environment
  }
}

resource "aws_efs_mount_target" "wordpress" {
  count          = length(aws_subnet.private)
  file_system_id = aws_efs_file_system.wordpress.id
  subnet_id      = aws_subnet.private[count.index].id

  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_elb" "wordpress" {
  name               = "${var.project_name}-elb"
  availability_zones = data.aws_availability_zones.available.names
  security_groups    = [aws_security_group.web_sg.id]

  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  tags = {
    Name        = "${var.project_name}-elb"
    Environment = var.environment
  }
}

resource "aws_autoscaling_group" "wordpress" {
  launch_configuration = aws_launch_configuration.wordpress.id
  min_size             = 2
  max_size             = 4
  vpc_zone_identifier  = aws_subnet.public[*].id
}

resource "aws_launch_configuration" "wordpress" {
  name          = "${var.project_name}-launch-config"
  image_id      = "ami-12345678"  # Example AMI for WordPress, change as needed
  instance_type = "t2.micro"
  key_name      = var.key_pair_name

  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd php php-mysql
              service httpd start
              chkconfig httpd on
              EOF

  security_groups = [aws_security_group.web_sg.id]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "wordpress" {
  identifier              = "${var.project_name}-db"
  engine                  = "mysql"
  instance_class          = "db.t2.small"
  allocated_storage       = 20
  name                    = "wordpress"
  username                = "admin"
  password                = "admin123"
  multi_az                = true
  vpc_security_group_ids  = [aws_security_group.db_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.wordpress.name
  skip_final_snapshot     = true
  publicly_accessible     = false

  tags = {
    Name        = "${var.project_name}-db"
    Environment = var.environment
  }
}

resource "aws_db_subnet_group" "wordpress" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
  }
}

resource "aws_s3_bucket" "wordpress" {
  bucket = "${var.project_name}-assets"
  acl    = "private"

  tags = {
    Name        = "${var.project_name}-s3-bucket"
    Environment = var.environment
  }
}

resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = "${aws_s3_bucket.wordpress.bucket}.s3.amazonaws.com"
    origin_id   = "${var.project_name}-s3-origin"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_cache_behavior {
    target_origin_id       = "${var.project_name}-s3-origin"
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

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name        = "${var.project_name}-cdn"
    Environment = var.environment
  }
}

resource "aws_route53_zone" "wordpress" {
  name = "example.com"  # Change to your domain

  tags = {
    Name        = "${var.project_name}-zone"
    Environment = var.environment
  }
}

resource "aws_route53_record" "wordpress" {
  zone_id = aws_route53_zone.wordpress.id
  name    = "www.example.com"  # Change to your desired record
  type    = "A"
  alias {
    name                   = aws_elb.wordpress.dns_name
    zone_id                = aws_elb.wordpress.zone_id
    evaluate_target_health = true
  }
}

output "vpc_id" {
  value = aws_vpc.wordpress.id
}

output "elb_dns_name" {
  value = aws_elb.wordpress.dns_name
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress.domain_name
}

output "db_instance_endpoint" {
  value = aws_db_instance.wordpress.endpoint
}
