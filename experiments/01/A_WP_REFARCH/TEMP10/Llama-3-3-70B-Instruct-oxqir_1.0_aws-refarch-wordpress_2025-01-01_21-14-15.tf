# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
}

# Define variables for user-configurable values
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
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

variable "cloudfront_domain" {
  type        = string
  description = "The domain name for the CloudFront distribution"
}

# Create VPC and networking resources
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

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name = "WordPressPublicRouteTable"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressPrivateRouteTable"
  }
}

resource "aws_subnet" "public_subnet1" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name = "WordPressPublicSubnet1"
  }
}

resource "aws_subnet" "private_subnet1" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name = "WordPressPrivateSubnet1"
  }
}

resource "aws_subnet" "public_subnet2" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-west-2b"
  tags = {
    Name = "WordPressPublicSubnet2"
  }
}

resource "aws_subnet" "private_subnet2" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-west-2b"
  tags = {
    Name = "WordPressPrivateSubnet2"
  }
}

resource "aws_route_table_association" "public_subnet1_assoc" {
  subnet_id      = aws_subnet.public_subnet1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnet1_assoc" {
  subnet_id      = aws_subnet.private_subnet1.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "public_subnet2_assoc" {
  subnet_id      = aws_subnet.public_subnet2.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnet2_assoc" {
  subnet_id      = aws_subnet.private_subnet2.id
  route_table_id = aws_route_table.private_route_table.id
}

# Create security groups for EC2 instances, RDS, and ELB
resource "aws_security_group" "ec2_security_group" {
  name        = "WordPressEC2SecurityGroup"
  description = "Allow inbound traffic on ports 80 and 22"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
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
    Name = "WordPressEC2SecurityGroup"
  }
}

resource "aws_security_group" "rds_security_group" {
  name        = "WordPressRDSSecurityGroup"
  description = "Allow inbound traffic on port 3306"
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
  tags = {
    Name = "WordPressRDSSecurityGroup"
  }
}

resource "aws_security_group" "elb_security_group" {
  name        = "WordPressELBSecurityGroup"
  description = "Allow inbound traffic on ports 80 and 443"
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
    Name = "WordPressELBSecurityGroup"
  }
}

# Create EC2 instances for WordPress
resource "aws_instance" "wordpress_instance1" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.ec2_security_group.id
  ]
  subnet_id = aws_subnet.public_subnet1.id
  key_name               = "wordpress-key"
  tags = {
    Name = "WordPressInstance1"
  }
}

resource "aws_instance" "wordpress_instance2" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.ec2_security_group.id
  ]
  subnet_id = aws_subnet.public_subnet2.id
  key_name               = "wordpress-key"
  tags = {
    Name = "WordPressInstance2"
  }
}

# Create Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_autoscaling_group" {
  name                      = "WordPressAutoScalingGroup"
  max_size                  = 5
  min_size                  = 2
  vpc_zone_identifier       = [aws_subnet.public_subnet1.id, aws_subnet.public_subnet2.id]
  launch_template {
    name    = "WordPressLaunchTemplate"
    version = "1"
  }
  tag {
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }
}

# Create RDS instance for WordPress database
resource "aws_db_instance" "wordpress_rds_instance" {
  identifier           = "wordpress-rds-instance"
  instance_class       = var.rds_instance_class
  engine               = "mysql"
  engine_version       = "8.0.20"
  username             = "wordpressuser"
  password             = "wordpresspassword"
  vpc_security_group_ids = [
    aws_security_group.rds_security_group.id
  ]
  db_subnet_group_name = "wordpress-rds-subnet-group"
  parameter_group_name = "wordpress-rds-parameter-group"
  tags = {
    Name = "WordPressRDSInstance"
  }
}

# Create Elastic Load Balancer for WordPress
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = [aws_subnet.public_subnet1.id, aws_subnet.public_subnet2.id]
  security_groups = [aws_security_group.elb_security_group.id]
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
  }
  tags = {
    Name = "WordPressELB"
  }
}

# Create CloudFront distribution for WordPress
resource "aws_cloudfront_distribution" "wordpress_cloudfront_distribution" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [var.cloudfront_domain]
  viewer_certificate {
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method = "sni-only"
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
    Name = "WordPressCloudFrontDistribution"
  }
}

# Create S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = "wordpress-static-assets"
  acl    = "private"
  versioning {
    enabled = true
  }
  tags = {
    Name = "WordPressS3Bucket"
  }
}

# Create Route 53 DNS configuration for WordPress
resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = "Z123456789012"
  name    = var.cloudfront_domain
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cloudfront_distribution.zone_id
    evaluate_target_health = false
  }
}

# Create CloudWatch dashboards for WordPress
resource "aws_cloudwatch_dashboard" "wordpress_cloudwatch_dashboard" {
  dashboard_name = "WordPressCloudWatchDashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        x    = 0
        y    = 0
        width = 12
        height = 6
        properties = {
          view        = "timeSeries"
          stacked     = false
          metrics     = [
            [
              "AWS/EC2",
              "CPUUtilization",
              "InstanceId",
              aws_instance.wordpress_instance1.id
            ]
          ]
          region      = "us-west-2"
          title       = "EC2 CPU Utilization"
          period     = 300
          stat       = "Average"
        }
      }
    ]
  })
}
