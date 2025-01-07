# Specify the provider and version
terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Configure the AWS provider
provider "aws" {
  region = "us-west-2"
}

# Define variables for VPC configuration
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "vpc_name" {
  type        = string
  default     = "wordpress-vpc"
  description = "Name of the VPC"
}

# Create VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name = var.vpc_name
  }
}

# Define variables for subnets
variable "public_subnet_cidr_blocks" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "CIDR blocks for the public subnets"
}

variable "private_subnet_cidr_blocks" {
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
  description = "CIDR blocks for the private subnets"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
  description = "Availability zones for the subnets"
}

# Create public subnets
resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnet_cidr_blocks)

  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidr_blocks[count.index]
  availability_zone = var.availability_zones[count.index % length(var.availability_zones)]

  tags = {
    Name = "public-subnet-${count.index + 1}"
  }
}

# Create private subnets
resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnet_cidr_blocks)

  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidr_blocks[count.index]
  availability_zone = var.availability_zones[count.index % length(var.availability_zones)]

  tags = {
    Name = "private-subnet-${count.index + 1}"
  }
}

# Create internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name = "wordpress-igw"
  }
}

# Create public route table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name = "public-route-table"
  }
}

# Create route to internet gateway
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public_subnets" {
  count = length(aws_subnet.public_subnets)

  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Define variables for security groups
variable "ec2_security_group_name" {
  type        = string
  default     = "wordpress-ec2-sg"
  description = "Name of the EC2 security group"
}

variable "rds_security_group_name" {
  type        = string
  default     = "wordpress-rds-sg"
  description = "Name of the RDS security group"
}

variable "elb_security_group_name" {
  type        = string
  default     = "wordpress-elb-sg"
  description = "Name of the ELB security group"
}

# Create security groups
resource "aws_security_group" "ec2_security_group" {
  name        = var.ec2_security_group_name
  description = "Security group for EC2 instances"
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
    Name = var.ec2_security_group_name
  }
}

resource "aws_security_group" "rds_security_group" {
  name        = var.rds_security_group_name
  description = "Security group for RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_security_group.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = var.rds_security_group_name
  }
}

resource "aws_security_group" "elb_security_group" {
  name        = var.elb_security_group_name
  description = "Security group for ELB"
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
    Name = var.elb_security_group_name
  }
}

# Create EC2 instances for WordPress
resource "aws_instance" "wordpress_instances" {
  count = 2

  ami           = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  vpc_security_group_ids = [
    aws_security_group.ec2_security_group.id
  ]
  subnet_id = aws_subnet.public_subnets[count.index].id

  tags = {
    Name = "wordpress-instance-${count.index + 1}"
  }
}

# Create RDS instance for WordPress database
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = "db.t2.micro"
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password"
  parameter_group_name = "default.mysql8.0"
  vpc_security_group_ids = [
    aws_security_group.rds_security_group.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name

  tags = {
    Name = "wordpress-rds"
  }
}

# Create DB subnet group
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private_subnets.*.id

  tags = {
    Name = "wordpress-db-subnet-group"
  }
}

# Create Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.elb_security_group.id]

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
  }

  tags = {
    Name = "wordpress-elb"
  }
}

# Create Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                 = "wordpress-asg"
  max_size             = 5
  min_size             = 2
  desired_capacity     = 2
  health_check_type    = "ELB"
  health_check_grace_period = 300
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier  = aws_subnet.public_subnets.*.id

  tag {
    key                 = "Name"
    value               = "wordpress-asg"
    propagate_at_launch = true
  }
}

# Create Launch Configuration for EC2 instances
resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  security_groups = [
    aws_security_group.ec2_security_group.id
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }

  enabled = true

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

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = []
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Create S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = "wordpress-static-assets"
  acl    = "private"

  tags = {
    Name = "wordpress-s3-bucket"
  }
}

# Create Route 53 DNS configuration
resource "aws_route53_record" "wordpress_dns_record" {
  zone_id = aws_route53_zone.wordpress_dns_zone.id
  name    = "wordpress.example.com"
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "wordpress_dns_zone" {
  name = "example.com"
}

# Output critical information
output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3_bucket.id
}

output "wordpress_dns_record_name" {
  value = aws_route53_record.wordpress_dns_record.name
}
