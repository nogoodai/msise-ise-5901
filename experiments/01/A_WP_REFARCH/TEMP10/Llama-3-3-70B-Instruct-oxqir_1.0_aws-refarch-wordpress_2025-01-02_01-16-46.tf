provider "aws" {
  region = "us-west-2"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "A list of availability zones"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "The instance type for the EC2 instances"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c2b8ca1dad44712c"
  description = "The ID of the AMI to use for the EC2 instances"
}

variable "database_instance_class" {
  type        = string
  default     = "db.t2.micro"
  description = "The instance class for the RDS database instance"
}

variable "cloudfront_domain_name" {
  type        = string
  default     = "example.com"
  description = "The domain name for the CloudFront distribution"
}

variable "route53_domain_name" {
  type        = string
  default     = "example.com"
  description = "The domain name for the Route 53 hosted zone"
}

variable "wordpress_admin_password" {
  type        = string
  sensitive   = true
}

# VPC Configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Project     = "WordPress"
    Environment = "Production"
  }
}

# Subnets
resource "aws_subnet" "public_subnets" {
  count             = 3
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  vpc_id            = aws_vpc.wordpress_vpc.id
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PublicSubnet-${count.index + 1}"
    Project     = "WordPress"
    Environment = "Production"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = 3
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 3)
  vpc_id            = aws_vpc.wordpress_vpc.id
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PrivateSubnet-${count.index + 1}"
    Project     = "WordPress"
    Environment = "Production"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Project     = "WordPress"
    Environment = "Production"
  }
}

# Route Tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Project     = "WordPress"
    Environment = "Production"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Project     = "WordPress"
    Environment = "Production"
  }
}

# Route table associations
resource "aws_route_table_association" "public_route_table_association" {
  count          = 3
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_route_table_association" {
  count          = 3
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Routes
resource "aws_route" "internet_gateway_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Security Groups
resource "aws_security_group" "wordpress_ec2_sg" {
  name        = "WordPressEC2SG"
  description = "Allow incoming HTTP and HTTPS traffic"
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
    Name        = "WordPressEC2SG"
    Project     = "WordPress"
    Environment = "Production"
  }
}

resource "aws_security_group" "wordpress_rds_sg" {
  name        = "WordPressRDSSG"
  description = "Allow incoming MySQL traffic"
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
    Name        = "WordPressRDSSG"
    Project     = "WordPress"
    Environment = "Production"
  }
}

# EC2 Instances
resource "aws_instance" "wordpress_ec2" {
  count                  = 3
  ami                    = var.ami_id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_ec2_sg.id]
  subnet_id              = aws_subnet.public_subnets[count.index].id
  key_name               = "wordpress-key"
  tags = {
    Name        = "WordPressEC2-${count.index + 1}"
    Project     = "WordPress"
    Environment = "Production"
  }
}

# RDS Instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = var.database_instance_class
  multi_az             = true
  vpc_security_group_ids = [aws_security_group.wordpress_rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_sng.name
  tags = {
    Name        = "WordPressRDS"
    Project     = "WordPress"
    Environment = "Production"
  }
}

resource "aws_db_subnet_group" "wordpress_rds_sng" {
  name       = "WordPressRDS-SNG"
  subnet_ids = aws_subnet.private_subnets.*.id

  tags = {
    Name        = "WordPressRDS-SNG"
    Project     = "WordPress"
    Environment = "Production"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_ec2_sg.id]

  listener {
    lb_port       = 80
    lb_protocol   = "http"
    instance_port = 80
    instance_protocol = "http"
  }

  tags = {
    Name        = "WordPressELB"
    Project     = "WordPress"
    Environment = "Production"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_ec2_asg" {
  name                      = "WordPressEC2ASG"
  launch_configuration      = aws_launch_configuration.wordpress_ec2_lc.name
  min_size                  = 3
  max_size                  = 5
  health_check_grace_period = 300
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id

  tag {
    key                 = "Name"
    value               = "WordPressEC2ASG"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = "WordPress"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "Production"
    propagate_at_launch = true
  }
}

# Launch Configuration
resource "aws_launch_configuration" "wordpress_ec2_lc" {
  name            = "WordPressEC2LC"
  image_id        = var.ami_id
  instance_type   = var.instance_type
  security_groups = [aws_security_group.wordpress_ec2_sg.id]

  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

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
    default_ttl           = 3600
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

# S3 Bucket
resource "aws_s3_bucket" "wordpress_s3" {
  bucket        = "wordpress-s3-bucket"
  force_destroy = true
  tags = {
    Name        = "WordPressS3"
    Project     = "WordPress"
    Environment = "Production"
  }
}

# Route 53 Hosted Zone
resource "aws_route53_zone" "wordpress_r53" {
  name = var.route53_domain_name

  tags = {
    Name        = "WordPressR53"
    Project     = "WordPress"
    Environment = "Production"
  }
}

# Route 53 Record
resource "aws_route53_record" "wordpress_r53_record" {
  zone_id = aws_route53_zone.wordpress_r53.zone_id
  name    = var.route53_domain_name
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

# Outputs
output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "elb_zone_id" {
  value = aws_elb.wordpress_elb.zone_id
}

output "r53_zone_id" {
  value = aws_route53_zone.wordpress_r53.zone_id
}
