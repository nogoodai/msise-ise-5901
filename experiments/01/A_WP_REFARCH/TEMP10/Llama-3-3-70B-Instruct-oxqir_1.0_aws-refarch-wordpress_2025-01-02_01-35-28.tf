# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Provider configuration
provider "aws" {
  region = "us-west-2"
}

# Variables
variable "env" {
  default = "dev"
}

variable "project" {
  default = "wordpress"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "database_instance_class" {
  default = "db.t2.small"
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

# VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "${var.project}-vpc"
    Environment = var.env
  }
}

# Public subnets
resource "aws_subnet" "public_subnets" {
  count             = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = "${var.env}-${count.index + 1}"
  tags = {
    Name        = "${var.project}-public-subnet-${count.index + 1}"
    Environment = var.env
  }
}

# Private subnets
resource "aws_subnet" "private_subnets" {
  count             = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = "${var.env}-${count.index + 1}"
  tags = {
    Name        = "${var.project}-private-subnet-${count.index + 1}"
    Environment = var.env
  }
}

# Internet Gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "${var.project}-igw"
    Environment = var.env
  }
}

# Public route table
resource "aws_route_table" "wordpress_public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "${var.project}-public-rt"
    Environment = var.env
  }
}

# Private route table
resource "aws_route_table" "wordpress_private_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "${var.project}-private-rt"
    Environment = var.env
  }
}

# Public route
resource "aws_route" "wordpress_public_route" {
  route_table_id         = aws_route_table.wordpress_public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Private route
# resource "aws_route" "wordpress_private_route" {
#   route_table_id         = aws_route_table.wordpress_private_rt.id
#   destination_cidr_block = "0.0.0.0/0"
#   nat_gateway_id         = aws_nat_gateway.wordpress_nat.id
# }

# Route table associations
resource "aws_route_table_association" "public_rt_associations" {
  count          = 2
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.wordpress_public_rt.id
}

resource "aws_route_table_association" "private_rt_associations" {
  count          = 2
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.wordpress_private_rt.id
}

# Security group for EC2 instances
resource "aws_security_group" "wordpress_ec2_sg" {
  name        = "${var.project}-ec2-sg"
  description = "Security group for WordPress EC2 instances"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
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
    Name        = "${var.project}-ec2-sg"
    Environment = var.env
  }
}

# Security group for RDS
resource "aws_security_group" "wordpress_rds_sg" {
  name        = "${var.project}-rds-sg"
  description = "Security group for WordPress RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_ec2_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "${var.project}-rds-sg"
    Environment = var.env
  }
}

# Security group for ELB
resource "aws_security_group" "wordpress_elb_sg" {
  name        = "${var.project}-elb-sg"
  description = "Security group for WordPress ELB"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
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
    Name        = "${var.project}-elb-sg"
    Environment = var.env
  }
}

# EC2 instances for WordPress
resource "aws_instance" "wordpress_instance" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.wordpress_ec2_sg.id
  ]
  subnet_id = aws_subnet.public_subnets[0].id
  tags = {
    Name        = "${var.project}-instance"
    Environment = var.env
  }
}

# RDS instance for WordPress database
resource "aws_db_instance" "wordpress_rds_instance" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = var.database_instance_class
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password"
  vpc_security_group_ids = [
    aws_security_group.wordpress_rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_sng.name
  tags = {
    Name        = "${var.project}-rds-instance"
    Environment = var.env
  }
}

resource "aws_db_subnet_group" "wordpress_rds_sng" {
  name       = "wordpress-rds-sng"
  subnet_ids = aws_subnet.private_subnets.*.id
  tags = {
    Name        = "${var.project}-rds-sng"
    Environment = var.env
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "${var.project}-elb"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_elb_sg.id]
  listener {
    lb_port       = 80
    lb_protocol   = "http"
    instance_port = 80
    instance_protocol = "http"
  }
  tags = {
    Name        = "${var.project}-elb"
    Environment = var.env
  }
}

# Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "${var.project}-asg"
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  min_size            = 1
  max_size            = 3
  vpc_zone_identifier = aws_subnet.public_subnets[0].id
  tags = [
    {
      key                 = "Name"
      value               = "${var.project}-asg"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = var.env
      propagate_at_launch = true
    },
  ]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name            = "${var.project}-lc"
  image_id        = "ami-0c94855ba95c71c99"
  instance_type   = var.instance_type
  security_groups = [aws_security_group.wordpress_ec2_sg.id]
  user_data       = file("${path.module}/user-data.sh")
}

# CloudFront distribution for content delivery
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_instance.wordpress_instance.public_ip
    origin_id   = "wordpress"
  }
  enabled         = true
  is_ipv6_enabled = true

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.wordpress_bucket.id
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  tags = {
    Name        = "${var.project}-cfd"
    Environment = var.env
  }
}

# S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-bucket"
  acl    = "private"
  tags = {
    Name        = "${var.project}-bucket"
    Environment = var.env
  }
}

# Route 53 DNS configuration
resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "wordpress.example.com"
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
}

output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "instance_id" {
  value = aws_instance.wordpress_instance.id
}

output "rds_instance_id" {
  value = aws_db_instance.wordpress_rds_instance.id
}
