# Specify the provider and version
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.1.0"
    }
  }
  required_version = ">= 1.3.0"
}

# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Define variables for the VPC
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}

variable "vpc_name" {
  type        = string
  default     = "WordPressVPC"
  description = "The name of the VPC"
}

# Create the VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = var.vpc_name
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Create the public and private subnets
resource "aws_subnet" "public_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name        = "PublicSubnet${count.index + 1}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 2)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name        = "PrivateSubnet${count.index + 1}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Get the available availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Create the internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Create the public and private route tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Create the route for the public route table
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Associate the public subnets with the public route table
resource "aws_route_table_association" "public_subnet_association" {
  count          = 2
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Associate the private subnets with the private route table
resource "aws_route_table_association" "private_subnet_association" {
  count          = 2
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Define variables for the security groups
variable "web_server_security_group_name" {
  type        = string
  default     = "WordPressWebServerSG"
  description = "The name of the web server security group"
}

variable "database_security_group_name" {
  type        = string
  default     = "WordPressDatabaseSG"
  description = "The name of the database security group"
}

# Create the security groups
resource "aws_security_group" "web_server_security_group" {
  vpc_id      = aws_vpc.wordpress_vpc.id
  name        = var.web_server_security_group_name
  description = "Security group for the web server"

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
    Name        = var.web_server_security_group_name
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "database_security_group" {
  vpc_id      = aws_vpc.wordpress_vpc.id
  name        = var.database_security_group_name
  description = "Security group for the database"

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server_security_group.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = var.database_security_group_name
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Define variables for the EC2 instance
variable "ec2_instance_type" {
  type        = string
  default     = "t2.micro"
  description = "The instance type for the EC2 instance"
}

variable "ec2_ami_id" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
  description = "The ID of the AMI for the EC2 instance"
}

# Create the EC2 instance
resource "aws_instance" "wordpress_ec2" {
  ami           = var.ec2_ami_id
  instance_type = var.ec2_instance_type
  vpc_security_group_ids = [
    aws_security_group.web_server_security_group.id
  ]
  subnet_id = aws_subnet.public_subnet[0].id
  key_name               = "wordpress-ec2-key"
  tags = {
    Name        = "WordPressEC2"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Define variables for the RDS instance
variable "rds_instance_class" {
  type        = string
  default     = "db.t2.micro"
  description = "The instance class for the RDS instance"
}

variable "rds_engine" {
  type        = string
  default     = "mysql"
  description = "The engine for the RDS instance"
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
  vpc_security_group_ids = [
    aws_security_group.database_security_group.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  tags = {
    Name        = "WordPressRDS"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Create the RDS subnet group
resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = aws_subnet.private_subnet[*].id
  tags = {
    Name        = "WordPressRDSSubnetGroup"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Define variables for the Elastic Load Balancer
variable "elb_name" {
  type        = string
  default     = "WordPressELB"
  description = "The name of the Elastic Load Balancer"
}

# Create the Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = var.elb_name
  subnets         = aws_subnet.public_subnet[*].id
  security_groups = [aws_security_group.web_server_security_group.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  tags = {
    Name        = var.elb_name
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Define variables for the Auto Scaling Group
variable "asg_name" {
  type        = string
  default     = "WordPressASG"
  description = "The name of the Auto Scaling Group"
}

variable "asg_min_size" {
  type        = number
  default     = 1
  description = "The minimum size of the Auto Scaling Group"
}

variable "asg_max_size" {
  type        = number
  default     = 5
  description = "The maximum size of the Auto Scaling Group"
}

# Create the Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = var.asg_name
  max_size                  = var.asg_max_size
  min_size                  = var.asg_min_size
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = aws_subnet.public_subnet[*].id
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
  name          = "wordpress-lc"
  image_id      = var.ec2_ami_id
  instance_type = var.ec2_instance_type
  security_groups = [
    aws_security_group.web_server_security_group.id
  ]
  key_name               = "wordpress-ec2-key"
  user_data              = "apt-get update && apt-get install -y apache2"
}

# Define variables for the CloudFront distribution
variable "cloudfront_distribution_name" {
  type        = string
  default     = "WordPressCloudFront"
  description = "The name of the CloudFront distribution"
}

# Create the CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cloudfront" {
  origin {
    domain_name = aws_s3_bucket.wordpress_s3.bucket
    origin_id   = "WordPressS3Origin"
  }
  enabled         = true
  is_ipv6_enabled = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WordPressS3Origin"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl           = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name        = var.cloudfront_distribution_name
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Create the S3 bucket
resource "aws_s3_bucket" "wordpress_s3" {
  bucket        = "wordpress-s3-bucket"
  acl           = "private"
  force_destroy = true
  tags = {
    Name        = "WordPressS3Bucket"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Define variables for the Route 53 DNS configuration
variable "route53_zone_name" {
  type        = string
  default     = "example.com"
  description = "The name of the Route 53 zone"
}

# Create the Route 53 zone
resource "aws_route53_zone" "wordpress_route53" {
  name = var.route53_zone_name
  tags = {
    Name        = "WordPressRoute53Zone"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Create the Route 53 record
resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53.zone_id
  name    = var.route53_zone_name
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

# Output the Elastic Load Balancer DNS name
output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

# Output the CloudFront distribution domain name
output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cloudfront.domain_name
}

# Output the Route 53 zone ID
output "route53_zone_id" {
  value = aws_route53_zone.wordpress_route53.zone_id
}
