# Configure the AWS provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.1.0"
    }
  }
}

# Provider configuration
provider "aws" {
  region = "us-west-2"
}

# VPC configuration
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "The availability zones for the VPC"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Subnet configuration
resource "aws_subnet" "public_subnets" {
  count             = 3
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PublicSubnet-${count.index + 1}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = 3
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 3)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PrivateSubnet-${count.index + 1}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Internet Gateway configuration
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Route Table configuration
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

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
}

# Security Group configuration
resource "aws_security_group" "web_server_sg" {
  name        = "WordPressWebServerSG"
  vpc_id      = aws_vpc.wordpress_vpc.id
  description = "Security group for WordPress web servers"

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
    Name        = "WordPressWebServerSG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "wordpress_db_sg" {
  name        = "WordPressDBSG"
  vpc_id      = aws_vpc.wordpress_vpc.id
  description = "Security group for WordPress database"

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WordPressDBSG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# EC2 instance configuration
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "wordpress_ec2" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  vpc_security_group_ids = [
    aws_security_group.web_server_sg.id
  ]
  subnet_id = aws_subnet.public_subnets[0].id
  tags = {
    Name        = "WordPressEC2"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# RDS instance configuration
resource "aws_db_instance" "wordpress_db" {
  identifier        = "wordpressdb"
  engine            = "mysql"
  engine_version    = "8.0.28"
  instance_class    = "db.t2.micro"
  allocated_storage = 20
  storage_type      = "gp2"
  backup_retention_period = 7
  availability_zone = var.availability_zones[0]
  vpc_security_group_ids = [
    aws_security_group.wordpress_db_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  parameter_group_name = aws_db_parameter_group.wordpress_db_parameter_group.name
  tags = {
    Name        = "WordPressDB"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpressdb-subnet-group"
  subnet_ids = aws_subnet.private_subnets[*].id
  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_db_parameter_group" "wordpress_db_parameter_group" {
  name        = "wordpressdb-parameter-group"
  family      = "mysql8.0"
  description = "Parameter group for WordPress database"
  tags = {
    Name        = "WordPressDBParameterGroup"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# ELB configuration
resource "aws_alb" "wordpress_alb" {
  name            = "wordpress-alb"
  subnets         = aws_subnet.public_subnets[*].id
  security_groups = [aws_security_group.web_server_sg.id]
  tags = {
    Name        = "WordPressALB"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_alb_target_group" "wordpress_alb_target_group" {
  name     = "wordpress-alb-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressALBTargetGroup"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_alb_listener" "wordpress_alb_listener" {
  load_balancer_arn = aws_alb.wordpress_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.wordpress_alb_target_group.arn
    type             = "forward"
  }
}

# Auto Scaling Group configuration
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 1
  launch_configuration      = aws_launch_configuration.wordpress_launch_configuration.name
  vpc_zone_identifier       = aws_subnet.public_subnets[*].id
  target_group_arns        = [aws_alb_target_group.wordpress_alb_target_group.arn]
  tags = {
    Name        = "WordPressASG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name          = "wordpress-launch-configuration"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  security_groups = [
    aws_security_group.web_server_sg.id
  ]
  user_data = file("./install_wordpress.sh")
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name        = "WordPressLaunchConfiguration"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# CloudFront distribution configuration
resource "aws_cloudfront_distribution" "wordpress_cloudfront" {
  enabled = true
  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = "WordPressALB"
  }
  aliases             = ["example.com", "www.example.com"]
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]
    target_origin_id = "WordPressALB"
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
  }

  tags = {
    Name        = "WordPressCloudFront"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# S3 bucket configuration
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket        = "example-wordpress-bucket"
  force_destroy = true
  acl           = "private"

  tags = {
    Name        = "WordPressS3Bucket"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_route53_zone" {
  name = "example.com"
  tags = {
    Name        = "WordPressRoute53Zone"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.zone_id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_alb.wordpress_alb.dns_name
    zone_id                = aws_alb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

output "wordpress_alb_dns_name" {
  value = aws_alb.wordpress_alb.dns_name
}

output "wordpress_cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cloudfront.domain_name
}

output "wordpress_route53_zone_id" {
  value = aws_route53_zone.wordpress_route53_zone.zone_id
}
