# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.1.0"
    }
  }
}

# Specify provider configuration
provider "aws" {
  region = "us-west-2"
}

# Configure VPC
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
  }
}

# Configure subnets
variable "public_subnets_cidr" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "CIDR blocks for public subnets"
}

variable "private_subnets_cidr" {
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
  description = "CIDR blocks for private subnets"
}

resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnets_cidr)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnets_cidr[count.index]
  availability_zone = "${aws_vpc.wordpress_vpc.region}${count.index % 2 + 1}a"
  tags = {
    Name        = "PublicSubnet${count.index + 1}"
    Environment = "production"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnets_cidr)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnets_cidr[count.index]
  availability_zone = "${aws_vpc.wordpress_vpc.region}${count.index % 2 + 1}b"
  tags = {
    Name        = "PrivateSubnet${count.index + 1}"
    Environment = "production"
  }
}

# Configure route tables and internet gateway
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
    gateway_id = aws_internet_gateway.wordpress_igw.id
    cidr_block = "0.0.0.0/0"
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

# Associate route tables with subnets
resource "aws_route_table_association" "public_route_table_association" {
  count          = length(aws_subnet.public_subnets)
  route_table_id = aws_route_table.public_route_table.id
  subnet_id      = aws_subnet.public_subnets[count.index].id
}

resource "aws_route_table_association" "private_route_table_association" {
  count          = length(aws_subnet.private_subnets)
  route_table_id = aws_route_table.private_route_table.id
  subnet_id      = aws_subnet.private_subnets[count.index].id
}

# Configure security groups
variable "admin_access_cidr" {
  type        = string
  default     = "0.0.0.0/0"
  description = "CIDR block for administrative access"
}

resource "aws_security_group" "web_server_sg" {
  name        = "WordPressWebServerSG"
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
    cidr_blocks = [var.admin_access_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WordPressWebServerSG"
    Environment = "production"
  }
}

resource "aws_security_group" "database_sg" {
  name        = "WordPressDatabaseSG"
  description = "Security group for WordPress database"
  vpc_id      = aws_vpc.wordpress_vpc.id

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
    Name        = "WordPressDatabaseSG"
    Environment = "production"
  }
}

# Configure EC2 instances for WordPress
variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for WordPress EC2 instances"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c55b159cbfafe1f0"
  description = "AMI ID for WordPress EC2 instances"
}

resource "aws_instance" "wordpress_ec2" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.web_server_sg.id
  ]
  subnet_id = aws_subnet.public_subnets[0].id
  tags = {
    Name        = "WordPressEC2"
    Environment = "production"
  }
}

# Configure RDS instance for WordPress database
variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Instance class for RDS instance"
}

variable "rds_engine" {
  type        = string
  default     = "mysql"
  description = "Engine for RDS instance"
}

resource "aws_db_instance" "wordpress_rds" {
  identifier        = "wordpress-rds"
  instance_class    = var.rds_instance_class
  engine            = var.rds_engine
  engine_version     = "8.0.20"
  license_model     = "general-public-license"
  allocated_storage = 20
  storage_type      = "gp2"
  vpc_security_group_ids = [
    aws_security_group.database_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  parameter_group_name = aws_db_parameter_group.wordpress_rds_parameter_group.name
  username             = "admin"
  password             = "password123"
  publicly_accessible  = false
  skip_final_snapshot  = true
  deletion_protection = false
  tags = {
    Name        = "WordPressRDS"
    Environment = "production"
  }
}

resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = aws_subnet.private_subnets.*.id

  tags = {
    Name        = "WordPressRDSSubnetGroup"
    Environment = "production"
  }
}

resource "aws_db_parameter_group" "wordpress_rds_parameter_group" {
  name        = "wordpress-rds-parameter-group"
  family      = "mysql8.0"
  description = "Parameter group for WordPress RDS instance"

  tags = {
    Name        = "WordPressRDSParameterGroup"
    Environment = "production"
  }
}

# Configure Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.web_server_sg.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
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
  }
}

# Configure Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                 = "wordpress-asg"
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  min_size             = 1
  max_size             = 5
  vpc_zone_identifier = aws_subnet.public_subnets.*.id

  tags = [
    {
      key                 = "Name"
      value               = "WordPressASG"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.web_server_sg.id
  ]
  user_data = <<-EOF
              #!/bin/bash
              echo "Installing WordPress"
              EOF
}

# Configure CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }

  enabled         = true
  is_ipv6_enabled = true

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

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US"]
    }
  }

  tags = {
    Name        = "WordPressCFD"
    Environment = "production"
  }
}

# Configure S3 bucket
resource "aws_s3_bucket" "wordpress_s3" {
  bucket = "wordpress-s3-bucket"
  acl    = "private"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Name        = "WordPressS3"
    Environment = "production"
  }
}

# Configure Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_r53" {
  name = "example.com"

  tags = {
    Name        = "WordPressR53"
    Environment = "production"
  }
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

  depends_on = [aws_elb.wordpress_elb]
}
