# Define the Terraform provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.46.0"
    }
  }
  required_version = ">= 1.2.5"
}

# Configure the AWS provider
provider "aws" {
  region = var.region
}

# Define variables for the configuration
variable "region" {
  type        = string
  default     = "us-west-2"
  description = "AWS region"
}

variable "azs" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "Availability zones"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "VPC CIDR block"
}

variable "public_subnets" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  description = "Public subnet CIDR blocks"
}

variable "private_subnets" {
  type        = list(string)
  default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  description = "Private subnet CIDR blocks"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "EC2 instance type"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "RDS instance class"
}

variable "ec2_ami" {
  type        = string
  default     = "ami-0c2ab3b8efb09f272"
  description = "EC2 AMI ID"
}

variable "efs_performance_mode" {
  type        = string
  default     = "generalPurpose"
  description = "EFS performance mode"
}

variable "cloudfront_ssl_certificate" {
  type        = string
  default     = "arn:aws:iam::123456789012:server-certificate/cloudfront-ssl-certificate"
  description = "CloudFront SSL certificate ARN"
}

# Create a VPC
resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create public subnets
resource "aws_subnet" "public" {
  count = length(var.public_subnets)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnets[count.index]
  availability_zone = var.azs[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name        = "public-subnet-${count.index + 1}"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create private subnets
resource "aws_subnet" "private" {
  count = length(var.private_subnets)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.azs[count.index]
  tags = {
    Name        = "private-subnet-${count.index + 1}"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create an internet gateway
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags = {
    Name        = "wordpress-igw"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create a public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags = {
    Name        = "public-route-table"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create a private route table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags = {
    Name        = "private-route-table"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create route table associations
resource "aws_route_table_association" "public" {
  count = length(var.public_subnets)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = length(var.private_subnets)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Create a security group for the EC2 instances
resource "aws_security_group" "ec2" {
  name        = "wordpress-ec2-sg"
  description = "Security group for WordPress EC2 instances"
  vpc_id      = aws_vpc.this.id

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
    Name        = "wordpress-ec2-sg"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create a security group for the RDS instance
resource "aws_security_group" "rds" {
  name        = "wordpress-rds-sg"
  description = "Security group for WordPress RDS instance"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "wordpress-rds-sg"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create an RDS instance
resource "aws_db_instance" "this" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = var.rds_instance_class
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password"
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name = aws_db_subnet_group.this.name
  skip_final_snapshot  = true
  tags = {
    Name        = "wordpress-rds"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create a DB subnet group
resource "aws_db_subnet_group" "this" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id
  tags = {
    Name        = "wordpress-db-subnet-group"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create an Elastic Load Balancer
resource "aws_elb" "this" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.public[*].id
  security_groups = [aws_security_group.ec2.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  tags = {
    Name        = "wordpress-elb"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create an Auto Scaling group
resource "aws_autoscaling_group" "this" {
  name                      = "wordpress-asg"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }
  vpc_zone_identifier = aws_subnet.public[*].id
  tags = [
    {
      key                 = "Name"
      value               = "wordpress-asg"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = "production"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = "wordpress"
      propagate_at_launch = true
    },
  ]
}

# Create a launch template
resource "aws_launch_template" "this" {
  name          = "wordpress-launch-template"
  image_id      = var.ec2_ami
  instance_type = var.instance_type
  key_name      = "wordpress-ec2-key"
  security_group_names = [aws_security_group.ec2.name]
  tags = {
    Name        = "wordpress-launch-template"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create an Elastic File System (EFS)
resource "aws_efs_file_system" "this" {
  creation_token = "wordpress-efs"

  tags = {
    Name        = "wordpress-efs"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create an EFS mount target
resource "aws_efs_mount_target" "this" {
  count = length(var.azs)

  file_system_id = aws_efs_file_system.this.id
  subnet_id      = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.ec2.id]
}

# Create a CloudFront distribution
resource "aws_cloudfront_distribution" "this" {
  origin {
    domain_name = aws_elb.this.dns_name
    origin_id   = "wordpress-elb-origin"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-elb-origin"

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

  tags = {
    Name        = "wordpress-cf"
    Environment = "production"
    Project     = "wordpress"
  }

  viewer_certificate {
    acm_certificate_arn = var.cloudfront_ssl_certificate
    ssl_support_method  = "sni-only"
  }
}

# Create an S3 bucket
resource "aws_s3_bucket" "this" {
  bucket = "wordpress-static-assets"
  acl    = "private"

  tags = {
    Name        = "wordpress-static-assets"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create a Route 53 hosted zone
resource "aws_route53_zone" "this" {
  name = "example.com"

  tags = {
    Name        = "example-com"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create a Route 53 record
resource "aws_route53_record" "this" {
  zone_id = aws_route53_zone.this.id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id               = aws_cloudfront_distribution.this.zone_id
    evaluate_target_health = false
  }
}
