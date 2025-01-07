# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Define variables
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  default = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  default = "10.0.2.0/24"
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

variable "rds_engine" {
  default = "mysql"
}

variable "ec2_key_pair_name" {
  default = "wordpress-ec2-key"
}

variable "bucket_name" {
  default = "wordpress-static-assets"
}

variable "domain_name" {
  default = "example.com"
}

# Create a VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

# Create public and private subnets
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidr
  availability_zone = "us-west-2a"
  tags = {
    Name = "PublicSubnet"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = "us-west-2a"
  tags = {
    Name = "PrivateSubnet"
  }
}

# Create an internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Create public and private route tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

# Associate public route table with public subnet
resource "aws_route_table_association" "public_subnet_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

# Associate private route table with private subnet
resource "aws_route_table_association" "private_subnet_assoc" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

# Create a route to the internet gateway in the public route table
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Create security groups for EC2 instances, RDS, and ELB
resource "aws_security_group" "ec2_sg" {
  name        = "WordPressEC2SG"
  description = "Security group for WordPress EC2 instances"
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
    Name = "WordPressEC2SG"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "WordPressRDSSG"
  description = "Security group for WordPress RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  tags = {
    Name = "WordPressRDSSG"
  }
}

resource "aws_security_group" "elb_sg" {
  name        = "WordPressELBSG"
  description = "Security group for WordPress ELB"
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
    Name = "WordPressELBSG"
  }
}

# Create an RDS instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = var.rds_engine
  engine_version       = "8.0.23"
  instance_class       = var.rds_instance_class
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password123"
  parameter_group_name = "default.mysql8.0"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.wordpress_rds_subnet_group.name
  skip_final_snapshot     = true
}

resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = [aws_subnet.private_subnet.id]
}

# Create an ELB
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = [aws_subnet.public_subnet.id]
  security_groups = [aws_security_group.elb_sg.id]

  listener {
    instance_port      = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  listener {
    instance_port      = 443
    instance_protocol = "https"
    lb_port           = 443
    lb_protocol       = "https"
    ssl_certificate_id = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  }
}

# Create an Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_ec2_asg" {
  name                      = "wordpress-ec2-asg"
  max_size                  = 3
  min_size                  = 1
  vpc_zone_identifier       = [aws_subnet.private_subnet.id]
  launch_configuration      = aws_launch_configuration.wordpress_ec2_lc.name
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true

  tag {
    key                 = "Name"
    value               = "WordPressEC2Instance"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress_ec2_lc" {
  name          = "wordpress-ec2-lc"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.ec2_sg.id]
  key_name               = var.ec2_key_pair_name
  user_data              = file("${path.module}/wordpress_user_data.sh")
}

# Create a CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WordPressELB"

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

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "sni-only"
  }
}

# Create an S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_static_assets" {
  bucket = var.bucket_name
  acl    = "private"

  tags = {
    Name        = var.bucket_name
    Environment = "production"
  }
}

# Create a Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_dns" {
  name = var.domain_name
}

resource "aws_route53_record" "wordpress_elb_dns" {
  zone_id = aws_route53_zone.wordpress_dns.id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "wordpress_cf_dns" {
  zone_id = aws_route53_zone.wordpress_dns.id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cf.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cf.zone_id
    evaluate_target_health = false
  }
}

# Output critical information
output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "cf_distribution_id" {
  value = aws_cloudfront_distribution.wordpress_cf.id
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_static_assets.id
}

output "rds_instance_id" {
  value = aws_db_instance.wordpress_rds.id
}

output "ec2_instance_id" {
  value = aws_autoscaling_group.wordpress_ec2_asg.id
}
