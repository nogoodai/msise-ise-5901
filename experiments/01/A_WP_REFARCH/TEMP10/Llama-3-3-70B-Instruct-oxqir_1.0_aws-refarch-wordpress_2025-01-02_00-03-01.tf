# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Define variables
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "VPC CIDR block"
}

variable "azs" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "List of availability zones"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Type of EC2 instance to use"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "RDS instance class"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
  description = "ID of the Amazon Linux 2 AMI"
}

variable "wordpress_db_username" {
  type        = string
  default     = "wordpressuser"
  description = "Username for the WordPress database"
}

variable "wordpress_db_password" {
  type        = string
  sensitive   = true
  default     = "wordpresspassword"
  description = "Password for the WordPress database"
}

variable "domain_name" {
  type        = string
  default     = "example.com"
  description = "Domain name for the website"
}

# Create a VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

# Create public and private subnets
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = var.azs[0]
  tags = {
    Name = "PublicSubnet"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = var.azs[0]
  tags = {
    Name = "PrivateSubnet"
  }
}

# Create an internet gateway and attach it to the VPC
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Create a public route table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicRouteTable"
  }
}

# Create a route to the internet gateway
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Associate the public route table with the public subnet
resource "aws_route_table_association" "public_route_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

# Create a private route table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

# Create an Elastic IP for the NAT gateway
resource "aws_eip" "nat_eip" {
  vpc = true
}

# Create a NAT gateway
resource "aws_nat_gateway" "wordpress_nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id
  tags = {
    Name = "WordPressNATGW"
  }
}

# Create a route to the NAT gateway
resource "aws_route" "private_route" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id          = aws_nat_gateway.wordpress_nat_gw.id
}

# Associate the private route table with the private subnet
resource "aws_route_table_association" "private_route_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

# Create a security group for the EC2 instances
resource "aws_security_group" "wordpress_ec2_sg" {
  name        = "wordpress-ec2-sg"
  description = "Security group for the WordPress EC2 instances"
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

# Create a security group for the RDS instance
resource "aws_security_group" "wordpress_rds_sg" {
  name        = "wordpress-rds-sg"
  description = "Security group for the WordPress RDS instance"
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
}

# Create an RDS instance
resource "aws_db_instance" "wordpress_rds" {
  identifier        = "wordpress-rds"
  instance_class    = var.rds_instance_class
  engine            = "mysql"
  username          = var.wordpress_db_username
  password          = var.wordpress_db_password
  vpc_security_group_ids = [aws_security_group.wordpress_rds_sg.id]
  availability_zone = var.azs[0]
  storage_type      = "gp2"
  allocated_storage = 20
  skip_final_snapshot = true
}

# Create an Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = [aws_subnet.public_subnet.id]
  security_groups = [aws_security_group.wordpress_ec2_sg.id]
}

# Create an Auto Scaling Group for the EC2 instances
resource "aws_autoscaling_group" "wordpress_ec2_asg" {
  name                      = "wordpress-ec2-asg"
  max_size                  = 5
  min_size                  = 1
  desired_capacity          = 1
  launch_configuration      = aws_launch_configuration.wordpress_launcher.name
  vpc_zone_identifier       = [aws_subnet.private_subnet.id]
  health_check_grace_period = 300
  health_check_type         = "EC2"
}

# Create a launch configuration for the EC2 instances
resource "aws_launch_configuration" "wordpress_launcher" {
  name          = "wordpress-launcher"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.wordpress_ec2_sg.id]
  lifecycle {
    create_before_destroy = true
  }
}

# Create a CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cloudfront" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }

  enabled = true

  default_root_object = "index.html"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

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
}

# Create an S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_static" {
  bucket = "wordpress-static-assets"
  acl    = "private"
}

# Create a Route 53 record for the website
resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cloudfront.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cloudfront.zone_id
    evaluate_target_health = false
  }
}

# Create a Route 53 zone for the website
resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
}

# Output the website URL
output "website_url" {
  value = "http://${aws_route53_record.wordpress_record.fqdn}"
}

# Output the RDS instance URL
output "rds_instance_url" {
  value = aws_db_instance.wordpress_rds.endpoint
}

# Output the S3 bucket URL
output "s3_bucket_url" {
  value = "https://${aws_s3_bucket.wordpress_static.bucket}.${aws_s3_bucket.wordpress_static.region}.amazonaws.com"
}
