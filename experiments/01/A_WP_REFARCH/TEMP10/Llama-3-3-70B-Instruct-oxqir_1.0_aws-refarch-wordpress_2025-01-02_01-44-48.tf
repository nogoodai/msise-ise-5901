# Define the required provider and version
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Define the provider configuration
provider "aws" {
  region = "us-west-2"
}

# Define variables for the VPC and networking resources
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "public_subnet_cidr_blocks" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidr_blocks" {
  type        = list(string)
  default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

# Create the VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the public subnets
resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnet_cidr_blocks)

  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidr_blocks[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PublicSubnet${count.index + 1}"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the private subnets
resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnet_cidr_blocks)

  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidr_blocks[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PrivateSubnet${count.index + 1}"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the public route table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the private route table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the route for the public route table
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Create the route table associations for the public subnets
resource "aws_route_table_association" "public_route_table_associations" {
  count = length(var.public_subnet_cidr_blocks)

  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Create the route table associations for the private subnets
resource "aws_route_table_association" "private_route_table_associations" {
  count = length(var.private_subnet_cidr_blocks)

  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Create the security group for the EC2 instances
resource "aws_security_group" "wordpress_ec2_sg" {
  name        = "WordPressEC2SG"
  description = "Security group for WordPress EC2 instances"
  vpc_id      = aws_vpc.wordpress_vpc.id

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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WordPressEC2SG"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the security group for the RDS instance
resource "aws_security_group" "wordpress_rds_sg" {
  name        = "WordPressRDSSG"
  description = "Security group for WordPress RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_ec2_sg.id]
  }

  tags = {
    Name        = "WordPressRDSSG"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the security group for the Elastic Load Balancer
resource "aws_security_group" "wordpress_elb_sg" {
  name        = "WordPressELBSG"
  description = "Security group for WordPress Elastic Load Balancer"
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
    Name        = "WordPressELBSG"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_elb_sg.id]

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
    ssl_certificate_id = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  }

  tags = {
    Name        = "WordPressELB"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the EC2 instances for WordPress
resource "aws_instance" "wordpress_ec2" {
  count = 2

  ami           = "ami-12345678"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.wordpress_ec2_sg.id]
  subnet_id = aws_subnet.public_subnets[count.index].id
  key_name               = "wordpress"
  user_data              = file("${path.module}/wordpress-userdata.sh")

  tags = {
    Name        = "WordPressEC2${count.index + 1}"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the Auto Scaling Group for the EC2 instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  max_size                  = 5
  min_size                  = 2
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id
  launch_configuration      = aws_launch_configuration.wordpress_lc.name

  tag {
    key                 = "Name"
    value               = "WordPressEC2"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "production"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = "wordpress"
    propagate_at_launch = true
  }
}

# Create the launch configuration for the Auto Scaling Group
resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = "ami-12345678"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.wordpress_ec2_sg.id]
  key_name               = "wordpress"
  user_data              = file("${path.module}/wordpress-userdata.sh")

  lifecycle {
    create_before_destroy = true
  }
}

# Create the RDS instance for the WordPress database
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = "db.t2.micro"
  name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = "wordpresspassword"
  vpc_security_group_ids = [aws_security_group.wordpress_rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  parameter_group_name = aws_db_parameter_group.wordpress_rds_parameter_group.name
  skip_final_snapshot  = true

  tags = {
    Name        = "WordPressRDS"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the DB subnet group for the RDS instance
resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "WordPressRDSSubnetGroup"
  subnet_ids = aws_subnet.private_subnets.*.id

  tags = {
    Name        = "WordPressRDSSubnetGroup"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the DB parameter group for the RDS instance
resource "aws_db_parameter_group" "wordpress_rds_parameter_group" {
  name   = "WordPressRDSParameterGroup"
  family = "mysql8.0"

  parameter {
    name  = "character_set_server"
    value = "utf8"
  }

  parameter {
    name  = "collation_server"
    value = "utf8_general_ci"
  }

  tags = {
    Name        = "WordPressRDSParameterGroup"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the CloudFront distribution for content delivery
resource "aws_cloudfront_distribution" "wordpress_cloudfront" {
  origin {
    domain_name = aws_s3_bucket.wordpress_s3.bucket_regional_domain_name
    origin_id   = "S3Origin"

    s3_origin_config {
      origin_access_identity = "origin-access-identity/cloudfront/EJ673K67PVROV"
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/404.html"
  }

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"

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
    Name        = "WordPressCloudFront"
    Environment = "production"
    Project     = "wordpress"
  }

  viewer_certificate {
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "sni-only"
  }
}

# Create the S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_s3" {
  bucket        = "wordpress-static-assets"
  force_destroy = true
  acl           = "private"

  tags = {
    Name        = "WordPressS3"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the Route 53 hosted zone for DNS configuration
resource "aws_route53_zone" "wordpress_route53" {
  name = "example.com"

  tags = {
    Name        = "WordPressRoute53"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the A record for the Elastic Load Balancer
resource "aws_route53_record" "wordpress_elb_record" {
  zone_id = aws_route53_zone.wordpress_route53.zone_id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

# Create the CNAME record for the CloudFront distribution
resource "aws_route53_record" "wordpress_cloudfront_record" {
  zone_id = aws_route53_zone.wordpress_route53.zone_id
  name    = "static.example.com"
  type    = "CNAME"
  ttl     = "300"
  records = [aws_cloudfront_distribution.wordpress_cloudfront.domain_name]
}

# Output the ARN of the RDS instance
output "wordpress_rds_arn" {
  value = aws_db_instance.wordpress_rds.arn
}

# Output the URL of the Elastic Load Balancer
output "wordpress_elb_url" {
  value = aws_elb.wordpress_elb.dns_name
}

# Output the URL of the CloudFront distribution
output "wordpress_cloudfront_url" {
  value = aws_cloudfront_distribution.wordpress_cloudfront.domain_name
}

# Output the ID of the S3 bucket
output "wordpress_s3_id" {
  value = aws_s3_bucket.wordpress_s3.id
}

# Output the name of the Route 53 hosted zone
output "wordpress_route53_name" {
  value = aws_route53_zone.wordpress_route53.name
}
