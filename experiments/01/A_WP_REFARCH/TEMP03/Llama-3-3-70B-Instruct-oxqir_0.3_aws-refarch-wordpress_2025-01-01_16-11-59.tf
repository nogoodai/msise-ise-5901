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

variable "ami_id" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
  description = "The ID of the AMI for the EC2 instances"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "The instance class for the RDS instance"
}

variable "rds_engine" {
  type        = string
  default     = "mysql"
  description = "The engine for the RDS instance"
}

variable "cloudfront_domain" {
  type        = string
  default     = "example.com"
  description = "The domain for the CloudFront distribution"
}

variable "route53_domain" {
  type        = string
  default     = "example.com"
  description = "The domain for the Route 53 hosted zone"
}

# Create the VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

# Create the subnets
resource "aws_subnet" "public_subnets" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PublicSubnet${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, length(var.availability_zones) + count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PrivateSubnet${count.index + 1}"
  }
}

# Create the internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Create the route tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

# Create the routes
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Associate the subnets with the route tables
resource "aws_route_table_association" "public_subnets_association" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnets_association" {
  count          = length(var.availability_zones)
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
    Name = "WordPressSG"
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
    Name = "RDSSG"
  }
}

# Create the EC2 instances
resource "aws_instance" "wordpress_instances" {
  count         = length(var.availability_zones)
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public_subnets[count.index].id
  vpc_security_group_ids = [
    aws_security_group.wordpress_sg.id
  ]
  key_name               = "wordpress_key"
  user_data              = file("${path.module}/wordpress_user_data.sh")
  tags = {
    Name = "WordPressInstance${count.index + 1}"
  }
}

# Create the RDS instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = var.rds_engine
  engine_version       = "8.0.28"
  instance_class       = var.rds_instance_class
  name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = "wordpresspassword"
  parameter_group_name = "default.mysql8.0"
  vpc_security_group_ids = [
    aws_security_group.rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  tags = {
    Name = "WordPressRDS"
  }
}

# Create the DB subnet group
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress_db_subnet_group"
  subnet_ids = aws_subnet.private_subnets.*.id
  tags = {
    Name = "WordPressDBSubnetGroup"
  }
}

# Create the Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_sg.id]
  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 80
    lb_protocol        = "http"
  }
  tags = {
    Name = "WordPressELB"
  }
}

# Create the Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id
  tags = [
    {
      key                 = "Name"
      value               = "WordPressASG"
      propagate_at_launch = true
    },
  ]
}

# Create the Launch Configuration
resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.wordpress_sg.id
  ]
  key_name               = "wordpress_key"
  user_data              = file("${path.module}/wordpress_user_data.sh")
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
  aliases             = [var.cloudfront_domain]
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.wordpress_acm.arn
    ssl_support_method  = "sni-only"
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
  tags = {
    Name = "WordPressCFD"
  }
}

# Create the ACM certificate
resource "aws_acm_certificate" "wordpress_acm" {
  domain_name       = var.cloudfront_domain
  validation_method = "DNS"
  tags = {
    Name = "WordPressACM"
  }
}

# Create the Route 53 hosted zone
resource "aws_route53_zone" "wordpress_r53" {
  name = var.route53_domain
  tags = {
    Name = "WordPressR53"
  }
}

# Create the Route 53 record
resource "aws_route53_record" "wordpress_r53_record" {
  zone_id = aws_route53_zone.wordpress_r53.zone_id
  name    = var.route53_domain
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

# Create the S3 bucket
resource "aws_s3_bucket" "wordpress_s3" {
  bucket = var.cloudfront_domain
  acl    = "private"
  tags = {
    Name = "WordPressS3"
  }
}

# Output the ELB DNS name
output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

# Output the CloudFront distribution domain name
output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cfd.domain_name
}

# Output the RDS instance endpoint
output "rds_instance_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}
