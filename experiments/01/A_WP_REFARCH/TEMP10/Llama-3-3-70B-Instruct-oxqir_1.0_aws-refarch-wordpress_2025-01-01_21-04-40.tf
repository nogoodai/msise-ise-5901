# Configure the AWS provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
}

# Variable definitions
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "instance_type" {
  default = "t2.micro"
}

variable "wp_version" {
  default = "latest"
}

variable "db_instance_class" {
  default = "db.t2.small"
}

variable "db_engine" {
  default = "mysql"
}

variable "db_username" {
  default = "wordpressuser"
}

variable "db_password" {
  default = "wordpresspassword"
}

variable "cf_distribution_comment" {
  default = "WordPress CloudFront Distribution"
}

variable "cf_certificate_arn" {
  default = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
}

variable "route53_domain" {
  default = "example.com"
}

# Create VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create subnets
resource "aws_subnet" "public_subnets" {
  count             = 3
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name        = "PublicSubnet${count.index + 1}"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = 3
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 3)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PrivateSubnet${count.index + 1}"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create route tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route" "public_internet_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Associate subnets with route tables
resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Create security groups
resource "aws_security_group" "wp_sg" {
  name        = "WordPressSecurityGroup"
  description = "Allow inbound HTTP and HTTPS traffic"
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
    Name        = "WordPressSecurityGroup"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "RDSSecurityGroup"
  description = "Allow inbound MySQL traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wp_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "RDSSecurityGroup"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create RDS instance
resource "aws_db_instance" "wordpress_db" {
  instance_class = var.db_instance_class
  engine         = var.db_engine
  username       = var.db_username
  password       = var.db_password
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  multi_az = true
  tags = {
    Name        = "WordPressDatabase"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "WordPressDBSubnetGroup"
  subnet_ids = aws_subnet.private_subnets[*].id
  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create EC2 instances for WordPress
resource "aws_instance" "wordpress_ec2" {
  count = 3
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.wp_sg.id]
  subnet_id = aws_subnet.public_subnets[count.index].id
  user_data = file("./wordpress_setup.sh")
  tags = {
    Name        = "WordPressEC2${count.index + 1}"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = aws_subnet.public_subnets[*].id
  security_groups = [aws_security_group.wp_sg.id]
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
    ssl_certificate_id = var.cf_certificate_arn
  }
  tags = {
    Name        = "WordPressELB"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                 = "WordPressASG"
  max_size             = 5
  min_size             = 3
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier = aws_subnet.public_subnets[*].id
  tags = [
    {
      key                 = "Name"
      value               = "WordPressASG"
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

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  security_groups = [aws_security_group.wp_sg.id]
  user_data = file("./wordpress_setup.sh")
  lifecycle {
    create_before_destroy = true
  }
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }
  enabled = true
  default_root_object = "index.html"
  alias = [var.route53_domain]
  custom_error_response {
    error_caching_min_ttl = 0
    error_code            = 404
    response_code         = 200
    response_page_path    = "/404.html"
  }
  custom_error_response {
    error_caching_min_ttl = 0
    error_code            = 500
    response_code         = 200
    response_page_path    = "/500.html"
  }
  viewer_certificate {
    acm_certificate_arn = var.cf_certificate_arn
    ssl_support_method  = "sni-only"
  }
  tags = {
    Name        = "WordPressCloudFront"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_s3" {
  bucket = var.route53_domain
  acl    = "public-read"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource = "arn:aws:s3:::${var.route53_domain}/*"
      },
    ]
  })
  tags = {
    Name        = "WordPressS3"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_dns" {
  name = var.route53_domain
  tags = {
    Name        = "WordPressDNS"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route53_record" "wordpress_elb_record" {
  zone_id = aws_route53_zone.wordpress_dns.zone_id
  name    = var.route53_domain
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "wordpress_cf_record" {
  zone_id = aws_route53_zone.wordpress_dns.zone_id
  name    = var.route53_domain
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cf.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cf.zone_id
    evaluate_target_health = false
  }
}

# Outputs
output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_cf_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cf.domain_name
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3.id
}

output "wordpress_dns_zone_id" {
  value = aws_route53_zone.wordpress_dns.zone_id
}

output "wordpress_db_instance_arn" {
  value = aws_db_instance.wordpress_db.arn
}

output "wordpress_asg_name" {
  value = aws_autoscaling_group.wordpress_asg.name
}

output "wordpress_lc_name" {
  value = aws_launch_configuration.wordpress_lc.name
}
