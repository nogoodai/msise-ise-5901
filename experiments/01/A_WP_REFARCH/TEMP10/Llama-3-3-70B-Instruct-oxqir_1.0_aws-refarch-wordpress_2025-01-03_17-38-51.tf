# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

# Define variables for the configuration
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "ec2_ami" {
  default = "ami-0c94855ba95c71c99"
}

variable "database_engine" {
  default = "mysql"
}

variable "database_password" {
  sensitive = true
}

variable "database_username" {
  default = "admin"
}

variable "rds_instance_class" {
  default = "db.t2.small"
}

variable "elasticache_node_type" {
  default = "cache.t2.micro"
}

variable "elasticache_engine" {
  default = "memcached"
}

variable "cloudfront_distribution_domain_name" {
  default = "example.com"
}

variable "route53_domain_name" {
  default = "example.com"
}

variable "s3_bucket_name" {
  default = "example-bucket"
}

# Create VPC and Subnets
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name        = "PublicSubnet"
    Environment = "production"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name        = "PrivateSubnet"
    Environment = "production"
  }
}

# Create Internet Gateway and Route Tables
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }

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

# Associate Route Tables with Subnets
resource "aws_route_table_association" "public_route_table_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_route_table_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

# Create Security Groups
resource "aws_security_group" "ec2_sg" {
  name        = "EC2SecurityGroup"
  description = "Allow inbound traffic to EC2 instances"
  vpc_id      = aws_vpc.wordpress_vpc.id

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
    Name        = "EC2SecurityGroup"
    Environment = "production"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "RDSSecurityGroup"
  description = "Allow inbound traffic to RDS instances"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  tags = {
    Name        = "RDSSecurityGroup"
    Environment = "production"
  }
}

resource "aws_security_group" "elb_sg" {
  name        = "ELBSecurityGroup"
  description = "Allow inbound traffic to ELB"
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
    Name        = "ELBSecurityGroup"
    Environment = "production"
  }
}

# Create EC2 Instances for WordPress
resource "aws_instance" "wordpress_instance" {
  ami           = var.ec2_ami
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.ec2_sg.id
  ]
  subnet_id = aws_subnet.public_subnet.id
  tags = {
    Name        = "WordPressInstance"
    Environment = "production"
  }
}

# Create RDS Instance for WordPress Database
resource "aws_db_instance" "wordpress_rds_instance" {
  allocated_storage = 20
  engine            = var.database_engine
  instance_class    = var.rds_instance_class
  db_name           = "wordpress"
  username         = var.database_username
  password         = var.database_password
  vpc_security_group_ids = [
    aws_security_group.rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  tags = {
    Name        = "WordPressRDSInstance"
    Environment = "production"
  }
}

# Create Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = [aws_subnet.public_subnet.id]
  security_groups = [aws_security_group.elb_sg.id]

  listener {
    lb_port       = 80
    lb_protocol   = "http"
    instance_port = 80
    instance_protocol = "http"
  }

  tags = {
    Name        = "WordPressELB"
    Environment = "production"
  }
}

# Create Auto Scaling Group for EC2 Instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "WordPressASG"
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier = aws_subnet.public_subnet.id
  min_size            = 1
  max_size            = 3
  desired_capacity    = 2
}

# Create Launch Configuration for EC2 Instances
resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = var.ec2_ami
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.ec2_sg.id
  ]
}

# Create S3 Bucket for Static Assets
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = var.s3_bucket_name
  tags = {
    Name        = "WordPressS3Bucket"
    Environment = "production"
  }
}

# Create CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cloudfront_distribution" {
  origin {
    domain_name = aws_s3_bucket.wordpress_s3_bucket.bucket_regional_domain_name
    origin_id   = "S3Origin"
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
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
      restrictions_type = "none"
    }
  }

  tags = {
    Name        = "WordPressCloudFrontDistribution"
    Environment = "production"
  }
}

# Create Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress_route53_zone" {
  name = var.route53_domain_name
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name    = var.route53_domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cloudfront_distribution.zone_id
    evaluate_target_health = false
  }
}

# Output critical information
output "wordpress_instance_id" {
  value = aws_instance.wordpress_instance.id
}

output "wordpress_rds_instance_id" {
  value = aws_db_instance.wordpress_rds_instance.id
}

output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3_bucket.bucket
}

output "wordpress_cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
}

output "wordpress_route53_zone_id" {
  value = aws_route53_zone.wordpress_route53_zone.id
}

output "wordpress_route53_record_name" {
  value = aws_route53_record.wordpress_route53_record.name
}
