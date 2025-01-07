# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
}

# Variables for VPC configuration
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "List of availability zones"
}

# VPC and networking resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

resource "aws_subnet" "wordpress_public_subnets" {
  count = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "WordPressPublicSubnet-${count.index}"
  }
}

resource "aws_subnet" "wordpress_private_subnets" {
  count = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, length(var.availability_zones) + count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "WordPressPrivateSubnet-${count.index}"
  }
}

resource "aws_route_table" "wordpress_public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name = "WordPressPublicRouteTable"
  }
}

resource "aws_route_table_association" "wordpress_public_route_table_associations" {
  count = length(aws_subnet.wordpress_public_subnets)
  subnet_id      = aws_subnet.wordpress_public_subnets[count.index].id
  route_table_id = aws_route_table.wordpress_public_route_table.id
}

resource "aws_route_table" "wordpress_private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.wordpress_nat_gateway.id
  }
  tags = {
    Name = "WordPressPrivateRouteTable"
  }
}

resource "aws_route_table_association" "wordpress_private_route_table_associations" {
  count = length(aws_subnet.wordpress_private_subnets)
  subnet_id      = aws_subnet.wordpress_private_subnets[count.index].id
  route_table_id = aws_route_table.wordpress_private_route_table.id
}

resource "aws_nat_gateway" "wordpress_nat_gateway" {
  allocation_id = aws_eip.wordpress_eip.id
  subnet_id     = aws_subnet.wordpress_public_subnets[0].id
  tags = {
    Name = "WordPressNATGateway"
  }
}

resource "aws_eip" "wordpress_eip" {
  vpc = true
  tags = {
    Name = "WordPressEIP"
  }
}

# Security groups for EC2 instances, RDS, and ELB
resource "aws_security_group" "wordpress_web_server_security_group" {
  name        = "WordPressWebServerSecurityGroup"
  description = "Security group for WordPress web server"
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
    Name = "WordPressWebServerSecurityGroup"
  }
}

resource "aws_security_group" "wordpress_rds_security_group" {
  name        = "WordPressRDSSecurityGroup"
  description = "Security group for WordPress RDS"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_web_server_security_group.id]
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
resource "aws_instance" "wordpress_instance" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.wordpress_private_subnets[0].id
  vpc_security_group_ids = [
    aws_security_group.wordpress_web_server_security_group.id
  ]
  key_name               = "wordpress-key"
  user_data              = filebase64("${path.module}/wordpress-install.sh")
  tags = {
    Name = "WordPressInstance"
  }
}

# RDS instance for the WordPress database
resource "aws_db_instance" "wordpress_rds_instance" {
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = "db.t2.micro"
  db_name              = "wordpressdb"
  db_username          = "wordpressuser"
  db_password          = "wordpresspassword"
  vpc_security_group_ids = [
    aws_security_group.wordpress_rds_security_group.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  parameter_group_name = aws_db_parameter_group.wordpress_rds_parameter_group.name
  tags = {
    Name = "WordPressRDSInstance"
  }
}

resource "aws_db_parameter_group" "wordpress_rds_parameter_group" {
  name        = "wordpress-rds-parameter-group"
  family      = "mysql8.0"
  description = "Parameter group for WordPress RDS"
  parameter {
    name  = "character_set_server"
    value = "utf8"
  }
  parameter {
    name  = "character_set_client"
    value = "utf8"
  }
  tags = {
    Name = "WordPressRDSParameterGroup"
  }
}

resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name        = "wordpress-rds-subnet-group"
  subnet_ids = [
    aws_subnet.wordpress_private_subnets[0].id,
    aws_subnet.wordpress_private_subnets[1].id
  ]
  description = "Subnet group for WordPress RDS"
  tags = {
    Name = "WordPressRDSSubnetGroup"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = [aws_subnet.wordpress_public_subnets[0].id, aws_subnet.wordpress_public_subnets[1].id]
  security_groups = [
    aws_security_group.wordpress_web_server_security_group.id
  ]
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
    ssl_certificate_id = "arn:aws:iam::123456789012:server-certificate/cert"
  }
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 10
  }
  cross_zone_load_balancing   = true
  idle_timeout                = 60
  connection_draining         = true
  connection_draining_timeout = 60
  tags = {
    Name = "WordPressELB"
  }
}

# Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_autoscaling_group" {
  name                      = "WordPressAutoScalingGroup"
  max_size                  = 5
  min_size                  = 2
  desired_capacity          = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_launch_configuration.name
  vpc_zone_identifier       = [
    aws_subnet.wordpress_private_subnets[0].id,
    aws_subnet.wordpress_private_subnets[1].id
  ]
  tags = [
    {
      key                 = "Name"
      value               = "WordPressAutoScalingGroup"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name            = "WordPressLaunchConfiguration"
  image_id        = "ami-0c94855ba95c71c99"
  instance_type  = "t2.micro"
  security_groups = [
    aws_security_group.wordpress_web_server_security_group.id
  ]
  key_name               = "wordpress-key"
  user_data              = filebase64("${path.module}/wordpress-install.sh")
  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront distribution for content delivery
resource "aws_cloudfront_distribution" "wordpress_cloudfront_distribution" {
  enabled         = true
  is_ipv6_enabled = true
  default_root_object = "index.html"
  origin {
    domain_name = aws_s3_bucket.wordpress_s3_bucket.bucket
    origin_id   = aws_s3_bucket.wordpress_s3_bucket.id
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn = "arn:aws:iam::123456789012:server-certificate/cert"
    ssl_support_method  = "sni-only"
  }
  tags = {
    Name = "WordPressCloudFrontDistribution"
  }
}

# S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = "wordpress-bucket"
  acl    = "public-read"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource = [
          aws_s3_bucket.wordpress_s3_bucket.arn,
          "${aws_s3_bucket.wordpress_s3_bucket.arn}/*"
        ]
      }
    ]
  })
  website {
    index_document = "index.html"
  }
  tags = {
    Name = "WordPressS3Bucket"
  }
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_route53_zone" {
  name = "example.com"
  tags = {
    Name = "WordPressRoute53Zone"
  }
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.zone_id
  name    = "example.com"
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id                = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "wordpress_cloudfront_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.zone_id
  name    = "example.com"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cloudfront_distribution.zone_id
    evaluate_target_health = false
  }
}

# Outputs
output "wordpress_rds_instance_address" {
  value = aws_db_instance.wordpress_rds_instance.address
}

output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
}
