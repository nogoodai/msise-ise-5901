# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Define provider configuration
provider "aws" {
  region = var.region
}

# Configure the VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.cidr_block
  tags = {
    Name = "WordPressVPC"
  }
}

# Configure the public and private subnets
resource "aws_subnet" "public_subnets" {
  count = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.cidr_block, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PublicSubnet${count.index}"
  }
}

resource "aws_subnet" "private_subnets" {
  count = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.cidr_block, 8, count.index + 2)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PrivateSubnet${count.index}"
  }
}

# Configure the internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Configure the public route table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicRouteTable"
  }
}

# Configure the public route
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Associate public route table with public subnets
resource "aws_route_table_association" "public_subnets" {
  count          = 2
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Configure the private route table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

# Associate private route table with private subnets
resource "aws_route_table_association" "private_subnets" {
  count          = 2
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security groups for EC2 instances, RDS, and ELB
resource "aws_security_group" "ec2_security_group" {
  name        = "WordPressEC2SecurityGroup"
  description = "Allow inbound HTTP/HTTPS and SSH access"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "HTTP access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS access"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH access"
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

resource "aws_security_group" "rds_security_group" {
  name        = "WordPressRDSSecurityGroup"
  description = "Allow inbound MySQL access from EC2 security group"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "MySQL access from EC2 security group"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.ec2_security_group.id]
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

# EC2 instances for WordPress
resource "aws_instance" "wordpress_ec2_instances" {
  count = 2
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.ec2_security_group.id]
  subnet_id = aws_subnet.public_subnets[count.index].id
  key_name = var.key_name

  tags = {
    Name = "WordPressEC2Instance${count.index}"
  }
}

# RDS instance for the WordPress database
resource "aws_db_instance" "wordpress_rds_instance" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t2.micro"
  db_name              = "wordpressdb"
  username             = var.rds_username
  password             = var.rds_password
  vpc_security_group_ids = [aws_security_group.rds_security_group.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  multi_az             = true
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress_db_subnet_group"
  subnet_ids = [for subnet in aws_subnet.private_subnets : subnet.id]

  tags = {
    Name = "WordPressDBSubnetGroup"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = [for subnet in aws_subnet.public_subnets : subnet.id]
  security_groups = [aws_security_group.ec2_security_group.id]

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
    ssl_certificate_id = var.ssl_certificate_id
  }

  tags = {
    Name = "WordPressELB"
  }
}

# Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_ec2_autoscaling_group" {
  name                 = "WordPressEC2AutoScalingGroup"
  max_size             = 5
  min_size             = 2
  desired_capacity     = 2
  health_check_type    = "EC2"
  health_check_grace_period = 300
  launch_configuration = aws_launch_configuration.wordpress_launch_configuration.name
  vpc_zone_identifier  = [for subnet in aws_subnet.public_subnets : subnet.id]

  tags = [
    {
      key                 = "Name"
      value               = "WordPressEC2AutoScalingGroup"
      propagate_at_launch = true
    },
  ]
}

resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name          = "WordPressLaunchConfiguration"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.ec2_security_group.id]
  key_name = var.key_name
  user_data = file("${path.module}/wordpress_user_data.sh")
}

# CloudFront distribution for content delivery
resource "aws_cloudfront_distribution" "wordpress_cloudfront_distribution" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }

  enabled = true

  default_root_object = "index.html"

  aliases = var.domain_names

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/404.html"
  }

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
    acm_certificate_arn = var.ssl_certificate_id
    ssl_support_method   = "sni-only"
  }
}

# Output critical information
output "wordpress_vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_rds_instance_endpoint" {
  value = aws_db_instance.wordpress_rds_instance.endpoint
}

output "wordpress_cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.wordpress_cloudfront_distribution.id
}

variable "region" {
  type        = string
  default     = "us-west-2"
}

variable "cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
}

variable "ami_id" {
  type        = string
  default     = "ami-0c2ab3b8efb09f272"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  type        = string
  default     = "wordpress-key"
}

variable "rds_username" {
  type        = string
  default     = "wordpressuser"
}

variable "rds_password" {
  type        = string
  default     = "wordpresspassword"
}

variable "domain_names" {
  type        = list(string)
  default     = ["example.com", "www.example.com"]
}

variable "ssl_certificate_id" {
  type        = string
  default     = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
}
