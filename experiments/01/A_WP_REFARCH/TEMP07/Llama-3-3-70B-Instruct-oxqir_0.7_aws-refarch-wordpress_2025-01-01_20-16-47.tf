provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

variable "environment" {
  default = "dev"
}

variable "project_name" {
  default = "wordpress-project"
}

variable "vpc_cidr_block" {
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  type = list(string)
  default = ["us-west-2a", "us-west-2b"]
}

variable "instance_type" {
  default = "t2.micro"
}

variable "ami_id" {
  default = "ami-0c94855ba95c71c99"
}

variable "rds_instance_class" {
  default = "db.t2.small"
}

variable "rds_username" {
  default = "wordpressuser"
}

variable "rds_password" {
  default = "wordpresspassword"
}

variable "rds_database_name" {
  default = "wordpressdb"
}

variable "cloudfront_domain_name" {
  default = "example.com"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "public_subnets" {
  count = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "${var.project_name}-public-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "private_subnets" {
  count = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 8, length(var.availability_zones) + count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "${var.project_name}-private-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table_association" "public_subnets_association" {
  count = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_security_group" "wordpress_sg" {
  name        = "${var.project_name}-wordpress-sg"
  description = "Allow HTTP and HTTPS traffic"
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
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "${var.project_name}-wordpress-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow MySQL traffic"
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
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_instance" "wordpress_instances" {
  count = length(var.availability_zones)
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public_subnets[count.index].id
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  tags = {
    Name        = "${var.project_name}-wordpress-instance-${count.index + 1}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_db_instance" "wordpress_rds" {
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = var.rds_instance_class
  allocated_storage    = 20
  storage_type         = "gp2"
  parameter_group_name = "default.mysql8.0"
  db_name              = var.rds_database_name
  username             = var.rds_username
  password             = var.rds_password
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  availability_zone = var.availability_zones[0]
  multi_az         = true
  tags = {
    Name        = "${var.project_name}-wordpress-rds"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_elb" "wordpress_elb" {
  name            = "${var.project_name}-wordpress-elb"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_sg.id]
  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
  listener {
    instance_port      = 443
    instance_protocol  = "https"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  }
  tags = {
    Name        = "${var.project_name}-wordpress-elb"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "${var.project_name}-wordpress-asg"
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  min_size                  = 1
  max_size                  = 5
  desired_capacity         = 2
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  tags = [
    {
      key                 = "Name"
      value               = "${var.project_name}-wordpress-asg"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = var.environment
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = var.project_name
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name            = "${var.project_name}-wordpress-lc"
  image_id        = var.ami_id
  instance_type   = var.instance_type
  security_groups = [aws_security_group.wordpress_sg.id]
  user_data       = file("${path.module}/user_data.sh")
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }
  enabled         = true
  is_ipv6_enabled = true
  aliases         = [var.cloudfront_domain_name]
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-elb"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  tags = {
    Name        = "${var.project_name}-wordpress-cdn"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_s3_bucket" "wordpress_static_assets" {
  bucket        = "${var.project_name}-wordpress-static-assets"
  acl           = "private"
  force_destroy = true
  tags = {
    Name        = "${var.project_name}-wordpress-static-assets"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name    = var.cloudfront_domain_name
  vpc {
    vpc_id = aws_vpc.wordpress_vpc.id
  }
  tags = {
    Name        = "${var.project_name}-wordpress-zone"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = var.cloudfront_domain_name
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
  tags = {
    Name        = "${var.project_name}-wordpress-record"
    Environment = var.environment
    Project     = var.project_name
  }
}

output "wordpress_vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "wordpress_cdn_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cdn.domain_name
}

output "wordpress_static_assets_bucket_name" {
  value = aws_s3_bucket.wordpress_static_assets.bucket
}

output "wordpress_zone_id" {
  value = aws_route53_zone.wordpress_zone.zone_id
}
