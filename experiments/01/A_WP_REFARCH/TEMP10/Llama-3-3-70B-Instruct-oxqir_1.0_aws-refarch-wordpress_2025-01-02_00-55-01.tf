provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

# Variables
variable "environment" {
  type        = string
  default     = "dev"
}

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

variable "instance_type" {
  type        = string
  default     = "t2.micro"
}

variable "database_instance_type" {
  type        = string
  default     = "db.t2.micro"
}

variable "domain_name" {
  type        = string
  default     = "example.com"
}

# VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = var.environment
  }
}

# Public subnets
resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  cidr_block        = var.public_subnet_cidrs[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  availability_zone = "us-west-2${count.index + 1}"
  tags = {
    Name        = "PublicSubnet${count.index + 1}"
    Environment = var.environment
  }
}

# Private subnets
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  cidr_block        = var.private_subnet_cidrs[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  availability_zone = "us-west-2${count.index + 1}"
  tags = {
    Name        = "PrivateSubnet${count.index + 1}"
    Environment = var.environment
  }
}

# Internet gateway
resource "aws_internet_gateway" "wordpress_gw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressGateway"
    Environment = var.environment
  }
}

# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = var.environment
  }
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_gw.id
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private route table
resource "aws_route_table" "private" {
  count = length(aws_subnet.private)
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable${count.index + 1}"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet(private))
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Security groups
resource "aws_security_group" "web_server" {
  name        = "WebServerSecurityGroup"
  description = "Allow inbound HTTP/HTTPS from the internet"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from the internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from the bastion host"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.3.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WebServerSecurityGroup"
    Environment = var.environment
  }
}

resource "aws_security_group" "database" {
  name        = "DatabaseSecurityGroup"
  description = "Allow inbound MySQL/Aurora from the web server"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "MySQL/Aurora from the web server"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.web_server.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "DatabaseSecurityGroup"
    Environment = var.environment
  }
}

# EC2 instances
resource "aws_instance" "wordpress" {
  count         = 2
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public[count.index].id
  vpc_security_group_ids = [aws_security_group.web_server.id]

  tags = {
    Name        = "WordPressInstance${count.index + 1}"
    Environment = var.environment
  }
}

# RDS instance
resource "aws_db_instance" "wordpress_database" {
  identifier        = "wordpress-database"
  instance_class    = var.database_instance_type
  engine            = "mysql"
  engine_version    = "8.0.20"
  allocated_storage = 20
  storage_type       = "gp2"
  username           = "admin"
  password           = "password123"
  vpc_security_group_ids = [aws_security_group.database.id]
  db_subnet_group_name = "wordpress-subnet-group"

  tags = {
    Name        = "WordPressDatabase"
    Environment = var.environment
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = aws_subnet.public.*.id
  security_groups = [aws_security_group.web_server.id]

  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 80
    lb_protocol        = "http"
  }

  tags = {
    Name        = "WordPressELB"
    Environment = var.environment
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  max_size                  = 5
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 2
  force_delete              = true
  launch_template {
    name    = "WordPressLaunchTemplate"
    version = "$Latest"
  }
  vpc_zone_identifier = aws_subnet.public.*.id

  tag {
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }
}

resource "aws_launch_template" "wordpress_lt" {
  name          = "WordPressLaunchTemplate"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.web_server.id]
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressOrigin"
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WordPressOrigin"

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
    Name        = "WordPressCloudFrontDistribution"
    Environment = var.environment
  }
}

# S3 bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket        = "wordpress-bucket"
  force_destroy = true

  tags = {
    Name        = "WordPressS3Bucket"
    Environment = var.environment
  }
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = true
  }
}

# Outputs
output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_asg_id" {
  value = aws_autoscaling_group.wordpress_asg.id
}

output "wordpress_rds_endpoint" {
  value = aws_db_instance.wordpress_database.endpoint
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_bucket.id
}

output "wordpress_route53_zone_id" {
  value = aws_route53_zone.wordpress_zone.id
}
