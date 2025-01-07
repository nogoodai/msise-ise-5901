provider "aws" {
  region = "us-west-2"
}

# Define variables for reusable values
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c2ab3b8efb09f272"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
}

variable "rds_engine" {
  type        = string
  default     = "mysql"
}

variable "elasticache_engine" {
  type        = string
  default     = "memcached"
}

variable "elasticache_node_type" {
  type        = string
  default     = "cache.t2.micro"
}

variable "cloudfront_distribution_domain" {
  type        = string
  default     = "example.com"
}

variable "cloudfront_distribution_origin" {
  type        = string
  default     = "alb"
}

variable "route53_domain_name" {
  type        = string
  default     = "example.com"
}

# Create VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

# Create public subnets
resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnet_cidrs)

  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "PublicSubnet-${count.index + 1}"
  }
}

# Create private subnets
resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "PrivateSubnet-${count.index + 1}"
  }
}

# Create internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name = "WordPressIGW"
  }
}

# Create public route table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }

  tags = {
    Name = "PublicRouteTable"
  }
}

# Create private route table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name = "PrivateRouteTable"
  }
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public_subnets_association" {
  count = length(var.public_subnet_cidrs)

  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Associate private subnets with private route table
resource "aws_route_table_association" "private_subnets_association" {
  count = length(var.private_subnet_cidrs)

  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Create security groups
resource "aws_security_group" "ec2_security_group" {
  name        = "EC2SecurityGroup"
  description = "Allow inbound HTTP and HTTPS"
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
}

resource "aws_security_group" "rds_security_group" {
  name        = "RDSSecurityGroup"
  description = "Allow inbound MySQL"
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
}

# Create RDS instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = var.rds_engine
  engine_version       = "5.7"
  instance_class       = var.rds_instance_class
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password123"
  parameter_group_name = "default.mysql5.7"
  vpc_security_group_ids = [aws_security_group.rds_security_group.id]
  skip_final_snapshot  = true
}

# Create ElasticLoad Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.ec2_security_group.id]

  listener {
    lb_port       = 80
    lb_protocol   = "http"
    instance_port = 80
    instance_protocol = "http"
  }

  listener {
    lb_port       = 443
    lb_protocol   = "https"
    instance_port = 80
    instance_protocol = "http"
    ssl_certificate_id = "arn:aws:iam::123456789012:server-certificate/wordpress-cert"
  }
}

# Create EC2 instances
resource "aws_instance" "wordpress_ec2" {
  count = 2

  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.ec2_security_group.id]
  subnet_id = aws_subnet.public_subnets[count.index].id
  key_name               = "wordpress-key"
  user_data = <<-EOF
              #!/bin/bash
              echo "Installing WordPress..."
              EOF
}

# Create Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  max_size                  = 5
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity          = 2
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_conf.name
}

resource "aws_launch_configuration" "wordpress_conf" {
  name          = "WordPressConf"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.ec2_security_group.id]
  key_name               = "wordpress-key"
  user_data = <<-EOF
              #!/bin/bash
              echo "Installing WordPress..."
              EOF
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
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Create S3 bucket
resource "aws_s3_bucket" "wordpress_s3" {
  bucket        = "wordpress-bucket"
  acl           = "private"
  force_destroy = true

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

# Create Route 53 record
resource "aws_route53_record" "wordpress_dns" {
  zone_id = aws_route53_zone.wordpress_dns_zone.id
  name    = var.route53_domain_name
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_zone" "wordpress_dns_zone" {
  name = var.route53_domain_name
}

output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3.bucket
}

output "cloudfront_distribution_domain" {
  value = aws_cloudfront_distribution.wordpress_cfd.domain_name
}
