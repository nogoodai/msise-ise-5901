# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Define variables for networking
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}

variable "public_subnets_cidr_blocks" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "The CIDR blocks for the public subnets"
}

variable "private_subnets_cidr_blocks" {
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
  description = "The CIDR blocks for the private subnets"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
  description = "The availability zones for the subnets"
}

# Create a VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr_block

  tags = {
    Name = "WordPressVPC"
  }
}

# Create public subnets
resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnets_cidr_blocks)
  cidr_block        = var.public_subnets_cidr_blocks[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "PublicSubnet-${count.index}"
  }
}

# Create private subnets
resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnets_cidr_blocks)
  cidr_block        = var.private_subnets_cidr_blocks[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "PrivateSubnet-${count.index}"
  }
}

# Create an internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name = "WordPressIGW"
  }
}

# Create a public route table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }

  tags = {
    Name = "PublicRouteTable"
  }
}

# Create a private route table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name = "PrivateRouteTable"
  }
}

# Associate public subnets with the public route table
resource "aws_route_table_association" "public_subnets_association" {
  count          = length(var.public_subnets_cidr_blocks)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Associate private subnets with the private route table
resource "aws_route_table_association" "private_subnets_association" {
  count          = length(var.private_subnets_cidr_blocks)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Define variables for security groups
variable "wordpress_sg_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "The CIDR blocks for the WordPress security group"
}

variable "rds_sg_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "The CIDR blocks for the RDS security group"
}

# Create a security group for the WordPress instances
resource "aws_security_group" "wordpress_sg" {
  name        = "WordPressSG"
  description = "Security group for WordPress instances"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.wordpress_sg_cidr_blocks
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.wordpress_sg_cidr_blocks
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

# Create a security group for the RDS instance
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

# Create an RDS instance
resource "aws_db_instance" "wordpress_rds" {
  instance_class = "db.t2.small"
  engine         = "mysql"
  engine_version = "8.0.21"
  db_name        = "wordpress_db"
  username       = "wordpress_user"
  password       = "wordpress_password"
  parameter_group_name = "default.mysql8.0"
  allocated_storage    = 20
  storage_type         = "gp2"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  publicly_accessible  = false
}

# Create a DB subnet group
resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "WordPressRDS"
  subnet_ids = aws_subnet.private_subnets.*.id

  tags = {
    Name = "WordPressRDS"
  }
}

# Create an ELB
resource "aws_elb" "wordpress_elb" {
  name               = "WordPressELB"
  subnets            = aws_subnet.public_subnets.*.id
  security_groups    = [aws_security_group.wordpress_sg.id]

  listener {
    lb_port           = 80
    lb_protocol       = "http"
    instance_port     = 80
    instance_protocol = "http"
  }

  tags = {
    Name = "WordPressELB"
  }
}

# Create an Auto Scaling group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "WordPressASG"
  max_size            = 3
  min_size            = 1
  health_check_grace_period = 300
  health_check_type       = "ELB"
  launch_template {
    name    = aws_launch_template.wordpress_launch_template.name
    version = aws_launch_template.wordpress_launch_template.latest_version_number
  }
}

# Create a launch template
resource "aws_launch_template" "wordpress_launch_template" {
  name                 = "WordPressLaunchTemplate"
  image_id             = "ami-0c94855ba95c71c99"
  instance_type        = "t2.micro"
  key_name             = "wordpress_key"
  security_group_names = [aws_security_group.wordpress_sg.name]
}

# Create an S3 bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-bucket"
  acl    = "private"

  tags = {
    Name = "WordPressBucket"
  }
}

# Create a CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "S3Origin"
  }

  enabled = true

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

  tags = {
    Name = "WordPressDistribution"
  }
}

# Create a Route 53 hosted zone
resource "aws_route53_zone" "wordpress_hosted_zone" {
  name = "example.com"

  tags = {
    Name = "WordPressHostedZone"
  }
}

# Create a Route 53 record
resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_hosted_zone.zone_id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_distribution.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_distribution.zone_id
    evaluate_target_health = false
  }
}
