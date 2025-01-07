# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Define variables for the configuration
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "The availability zones for the subnets"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "The instance type for the EC2 instances"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "The instance class for the RDS instance"
}

variable "wordpress_version" {
  type        = string
  default     = "latest"
  description = "The version of WordPress to install"
}

# Create the VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
  }
}

# Create the subnets
resource "aws_subnet" "public_subnets" {
  count             = 3
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PublicSubnet-${count.index}"
    Environment = "production"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = 3
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, count.index + 3)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PrivateSubnet-${count.index}"
    Environment = "production"
  }
}

# Create the internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
  }
}

# Create the route tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = "production"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = "production"
  }
}

# Create the route table associations
resource "aws_route_table_association" "public_route_table_associations" {
  count          = 3
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_route_table_associations" {
  count          = 3
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Create the security groups
resource "aws_security_group" "wordpress_sg" {
  name        = "WordPressSG"
  description = "Security group for WordPress instances"
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
    Name        = "WordPressSG"
    Environment = "production"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "RDSSG"
  description = "Security group for RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "RDSSG"
    Environment = "production"
  }
}

# Create the RDS instance
resource "aws_db_instance" "wordpress_rds" {
  instance_class = var.rds_instance_class
  engine         = "mysql"
  engine_version = "8.0.23"
  username       = "wordpress"
  password       = "password"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.wordpress_db_subnet_group.name
  tags = {
    Name        = "WordPressRDS"
    Environment = "production"
  }
}

# Create the DB subnet group
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "WordPressDBSubnetGroup"
  subnet_ids = aws_subnet.private_subnets.*.id
  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = "production"
  }
}

# Create the EC2 instances
resource "aws_instance" "wordpress_ec2" {
  count         = 3
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  subnet_id = aws_subnet.public_subnets[count.index].id
  user_data = file("${path.module}/wordpress.sh")
  tags = {
    Name        = "WordPressEC2-${count.index}"
    Environment = "production"
  }
}

# Create the Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_sg.id]
  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
  tags = {
    Name        = "WordPressELB"
    Environment = "production"
  }
}

# Create the Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                 = "WordPressASG"
  max_size             = 5
  min_size             = 3
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity          = 3
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id
  tags = {
    Name        = "WordPressASG"
    Environment = "production"
  }
}

# Create the Launch Configuration
resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  security_groups = [aws_security_group.wordpress_sg.id]
  user_data = file("${path.module}/wordpress.sh")
  lifecycle {
    create_before_destroy = true
  }
}

# Create the CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = ["example.com"]
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

# Create the S3 bucket
resource "aws_s3_bucket" "wordpress_s3" {
  bucket = "example.com"
  acl    = "private"
  tags = {
    Name        = "WordPressS3"
    Environment = "production"
  }
}

# Create the Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_r53" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress_r53_record" {
  zone_id = aws_route53_zone.wordpress_r53.zone_id
  name    = "example.com"
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

# Output the ELB DNS name
output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

# Output the CloudFront distribution domain name
output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cfd.domain_name
}

# Output the S3 bucket name
output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3.bucket
}

# Output the Route 53 DNS name
output "route53_dns_name" {
  value = aws_route53_zone.wordpress_r53.name
}
