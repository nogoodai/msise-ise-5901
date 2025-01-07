terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources in."
  default     = "us-east-1"
}

variable "project" {
  description = "The name of the project for naming and tagging."
  default     = "wordpress"
}

variable "environment" {
  description = "The environment, e.g., dev, stage, prod."
  default     = "prod"
}

variable "cidr_block" {
  description = "The CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets."
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

resource "aws_vpc" "main" {
  cidr_block = var.cidr_block
  tags = {
    Name        = "${var.project}-vpc"
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "${var.project}-igw"
    Environment = var.environment
  }
}

resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name        = "${var.project}-public-subnet-${count.index + 1}"
    Environment = var.environment
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name        = "${var.project}-private-subnet-${count.index + 1}"
    Environment = var.environment
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "${var.project}-public-rt"
    Environment = var.environment
  }
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_server" {
  vpc_id = aws_vpc.main.id
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
    Name        = "${var.project}-web-sg"
    Environment = var.environment
  }
}

resource "aws_security_group" "database" {
  vpc_id = aws_vpc.main.id
  ingress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
    security_groups = [aws_security_group.web_server.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "${var.project}-db-sg"
    Environment = var.environment
  }
}

data "aws_ami" "latest_ami" {
  owners = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.latest_ami.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public[0].id
  security_groups = ["${aws_security_group.web_server.id}"]
  key_name      = aws_key_pair.bastion_key.key_name
  tags = {
    Name        = "${var.project}-bastion"
    Environment = var.environment
  }
}

resource "aws_key_pair" "bastion_key" {
  key_name   = "${var.project}-bastion-key"
  public_key = var.ssh_public_key
}

variable "ssh_public_key" {
  description = "The public SSH key for accessing the bastion host."
  type        = string
}

resource "aws_eip" "bastion_ip" {
  instance = aws_instance.bastion.id
  tags = {
    Name        = "${var.project}-bastion-eip"
    Environment = var.environment
  }
}

resource "aws_elb" "web" {
  name               = "${var.project}-elb"
  availability_zones = data.aws_availability_zones.available.names

  security_groups = [aws_security_group.web_server.id]

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

  tags = {
    Name        = "${var.project}-web-elb"
    Environment = var.environment
  }
}

resource "aws_autoscaling_group" "web" {
  desired_capacity     = 2
  min_size             = 1
  max_size             = 4
  vpc_zone_identifier  = aws_subnet.public.*.id
  launch_configuration = aws_launch_configuration.web.id
  tags = [
    {
      key                 = "Name"
      value               = "${var.project}-web-asg"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = var.environment
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "web" {
  image_id          = data.aws_ami.latest_ami.id
  instance_type     = "t2.micro"
  security_groups   = [aws_security_group.web_server.id]
  user_data         = file("wordpress-setup.sh")
  associate_public_ip_address = true
  key_name          = aws_key_pair.bastion_key.key_name
}

resource "aws_rds_instance" "db" {
  allocated_storage    = 20
  engine               = "mysql"
  instance_class       = "db.t2.small"
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password123"
  skip_final_snapshot  = true
  multi_az             = true
  vpc_security_group_ids = [aws_security_group.database.id]
  db_subnet_group_name = aws_db_subnet_group.db.name
  tags = {
    Name        = "${var.project}-rds"
    Environment = var.environment
  }
}

resource "aws_db_subnet_group" "db" {
  name       = "${var.project}-db-subnets"
  subnet_ids = aws_subnet.private.*.id
  tags = {
    Name        = "${var.project}-db-subnets"
    Environment = var.environment
  }
}

resource "aws_s3_bucket" "assets" {
  bucket_prefix = "${var.project}-assets-"
  acl           = "private"
  tags = {
    Name        = "${var.project}-assets"
    Environment = var.environment
  }
}

resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = aws_s3_bucket.assets.bucket_regional_domain_name
    origin_id   = "${var.project}-s3-origin"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for ${var.project}"

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "${var.project}-s3-origin"
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

  tags = {
    Name        = "${var.project}-cloudfront"
    Environment = var.environment
  }
}

resource "aws_route53_zone" "main" {
  name = var.domain_name
  tags = {
    Name        = "${var.project}-dns"
    Environment = var.environment
  }
}

variable "domain_name" {
  description = "The domain name for the WordPress site."
  default     = "example.com"
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

data "aws_availability_zones" "available" {}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "elb_dns" {
  value = aws_elb.web.dns_name
}

output "db_endpoint" {
  value = aws_rds_instance.db.endpoint
}
