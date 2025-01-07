provider "aws" {
  region = var.aws_region
  version = ">= 5.1.0"
}

# Variables
variable "aws_region" {
  default = "us-west-2"
}

variable "vpc_cidr_block" {
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr_blocks" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidr_blocks" {
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "instance_type" {
  default = "t2.micro"
}

variable "ami_id" {
  default = "ami-0c2ab3b8efb09f272"
}

variable "ec2_key_pair_name" {
  default = "wordpress-ec2-key-pair"
}

variable "ec2_key_pair_public_key" {
  default = ""
}

variable "database_username" {
  default = "wordpress_user"
}

variable "database_password" {
  default = "wordpress_password"
}

variable "database_name" {
  default = "wordpress_db"
}

variable "wordpress_domain_name" {
  default = "wordpress.example.com"
}

variable "route53_zone_id" {
  default = "Z0181752LRSWRKXD5W3V"
}

variable "cloudfront_s3_origin_id" {
  default = "wordpress-s3-origin"
}

variable "cloudfront_s3_origin_domain_name" {
  default = "wordpress-s3-origin.s3.amazonaws.com"
}

variable "cloudfront_ssl_certificate_id" {
  default = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
}

# VPC and networking resources
resource "aws_vpc" "wordpress" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_internet_gateway" "wordpress" {
  vpc_id = aws_vpc.wordpress.id
  tags = {
    Name = "WordPressInternetGateway"
  }
}

resource "aws_subnet" "wordpress_public" {
  count = length(var.public_subnet_cidr_blocks)
  vpc_id = aws_vpc.wordpress.id
  cidr_block = var.public_subnet_cidr_blocks[count.index]
  availability_zone = "us-west-2${count.index + 1}"
  tags = {
    Name = "WordPressPublicSubnet${count.index + 1}"
  }
}

resource "aws_subnet" "wordpress_private" {
  count = length(var.private_subnet_cidr_blocks)
  vpc_id = aws_vpc.wordpress.id
  cidr_block = var.private_subnet_cidr_blocks[count.index]
  availability_zone = "us-west-2${count.index + 1}"
  tags = {
    Name = "WordPressPrivateSubnet${count.index + 1}"
  }
}

resource "aws_route_table" "wordpress_public" {
  vpc_id = aws_vpc.wordpress.id
  tags = {
    Name = "WordPressPublicRouteTable"
  }
}

resource "aws_route" "wordpress_public" {
  route_table_id = aws_route_table.wordpress_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.wordpress.id
}

resource "aws_route_table_association" "wordpress_public" {
  count = length(var.public_subnet_cidr_blocks)
  subnet_id = aws_subnet.wordpress_public[count.index].id
  route_table_id = aws_route_table.wordpress_public.id
}

# Security groups
resource "aws_security_group" "wordpress_ec2" {
  name        = "wordpress-ec2-sg"
  description = "Security group for WordPress EC2 instances"
  vpc_id      = aws_vpc.wordpress.id

  ingress {
    from_port   = 80
    to_port     = 80
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
    Name = "WordPressEC2SecurityGroup"
  }
}

resource "aws_security_group" "wordpress_rds" {
  name        = "wordpress-rds-sg"
  description = "Security group for WordPress RDS instance"
  vpc_id      = aws_vpc.wordpress.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.wordpress_ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WordPressRDSSecurityGroup"
  }
}

resource "aws_security_group" "wordpress_elb" {
  name        = "wordpress-elb-sg"
  description = "Security group for WordPress ELB"
  vpc_id      = aws_vpc.wordpress.id

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
    Name = "WordPressELBSecurityGroup"
  }
}

# EC2 instances
resource "aws_key_pair" "wordpress_ec2" {
  key_name   = var.ec2_key_pair_name
  public_key = var.ec2_key_pair_public_key
}

resource "aws_instance" "wordpress" {
  count = 2
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id = aws_subnet.wordpress_private[count.index].id
  vpc_security_group_ids = [aws_security_group.wordpress_ec2.id]
  key_name               = var.ec2_key_pair_name

  tags = {
    Name = "WordPressEC2Instance${count.index + 1}"
  }
}

# RDS instance
resource "aws_db_instance" "wordpress" {
  identifier        = "wordpress-db"
  engine            = "mysql"
  engine_version    = "8.0.23"
  instance_class    = "db.t2.micro"
  allocated_storage = 20
  storage_type      = "gp2"
  vpc_security_group_ids = [aws_security_group.wordpress_rds.id]
  db_subnet_group_name    = aws_db_subnet_group.wordpress.name
  parameter_group_name    = aws_db_parameter_group.wordpress.name
  username                = var.database_username
  password                = var.database_password
  name                    = var.database_name
  multi_az                = true

  tags = {
    Name = "WordPressRDSInstance"
  }
}

resource "aws_db_subnet_group" "wordpress" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.wordpress_private[*].id

  tags = {
    Name = "WordPressDBSubnetGroup"
  }
}

resource "aws_db_parameter_group" "wordpress" {
  name   = "wordpress-db-parameter-group"
  family = "mysql8.0"

  parameter {
    name  = "max_connections"
    value = "1000"
  }

  tags = {
    Name = "WordPressDBParameterGroup"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.wordpress_public[*].id
  security_groups = [aws_security_group.wordpress_elb.id]

  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 80
    lb_protocol        = "http"
  }

  listener {
    instance_port      = 443
    instance_protocol  = "https"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = var.cloudfront_ssl_certificate_id
  }

  tags = {
    Name = "WordPressELB"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress" {
  name                      = "wordpress-asg"
  max_size                  = 2
  min_size                  = 1
  desired_capacity          = 1
  health_check_grace_period = 300
  health_check_type         = "ELB"
  launch_configuration      = aws_launch_configuration.wordpress.name
  vpc_zone_identifier       = aws_subnet.wordpress_private[*].id

  tag {
    key                 = "Name"
    value               = "WordPressAsgInstance"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress" {
  name          = "wordpress-lc"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.wordpress_ec2.id]
  key_name               = var.ec2_key_pair_name

  user_data = file("${path.module}/wordpress_user_data.sh")

  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = var.cloudfront_s3_origin_domain_name
    origin_id   = var.cloudfront_s3_origin_id

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "http-only"
      origin_ssl_protocols     = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }

  enabled = true

  default_root_object = "index.html"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = var.cloudfront_ssl_certificate_id
    ssl_support_method   = "sni-only"
  }

  tags = {
    Name = "WordPressCloudFrontDistribution"
  }
}

# S3 bucket
resource "aws_s3_bucket" "wordpress" {
  bucket = "wordpress-s3-bucket"
  acl    = "private"

  tags = {
    Name = "WordPressS3Bucket"
  }
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wordpress" {
  name = var.wordpress_domain_name

  tags = {
    Name = "WordPressRoute53Zone"
  }
}

resource "aws_route53_record" "wordpress" {
  zone_id = aws_route53_zone.wordpress.id
  name    = var.wordpress_domain_name
  type    = "A"

  alias {
    name                   = aws_elb.wordpress.dns_name
    zone_id               = aws_elb.wordpress.zone_id
    evaluate_target_health = false
  }

  tags = {
    Name = "WordPressRoute53Record"
  }
}

output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress.dns_name
}

output "wordpress_cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress.domain_name
}

output "wordpress_rds_instance_address" {
  value = aws_db_instance.wordpress.address
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress.id
}

output "wordpress_ec2_instance_public_ips" {
  value = aws_instance.wordpress[*].public_ip
}

output "wordpress_autoscaling_group_name" {
  value = aws_autoscaling_group.wordpress.name
}
