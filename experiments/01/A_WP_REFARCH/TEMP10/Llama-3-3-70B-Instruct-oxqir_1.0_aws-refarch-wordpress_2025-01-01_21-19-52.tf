# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Define variables for resource names and tags
variable "project_name" {
  default = "wordpress-architecture"
}

variable "environment" {
  default = "production"
}

# Create VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Create subnets
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name        = "${var.project_name}-public-subnet"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name        = "${var.project_name}-private-subnet"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Create internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Create route tables
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "${var.project_name}-private-rt"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Associate route tables with subnets
resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_subnet_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

# Create security groups
resource "aws_security_group" "wordpress_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
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
    Name        = "${var.project_name}-wordpress-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
  }
  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Create Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "${var.project_name}-elb"
  subnets         = [aws_subnet.public_subnet.id]
  security_groups = [aws_security_group.wordpress_sg.id]
  listener {
    lb_port       = 80
    lb_protocol   = "http"
    instance_port = 80
    instance_protocol = "http"
  }
  tags = {
    Name        = "${var.project_name}-elb"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Create Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "${var.project_name}-asg"
  max_size            = 5
  min_size            = 2
  desired_capacity    = 3
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier = aws_subnet.private_subnet.id
  tags = [
    {
      key                 = "Name"
      value               = "${var.project_name}-asg"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = var.environment
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = var.project_name
      propagate_at_launch = true
    }
  ]
}

# Create Launch Configuration
resource "aws_launch_configuration" "wordpress_lc" {
  name          = "${var.project_name}-lc"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.wordpress_sg.id]
  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update
              sudo apt-get install -y apache2
              sudo service apache2 start
              EOF
}

# Create RDS instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage = 20
  instance_class    = "db.t2.micro"
  engine            = "mysql"
  username          = "wordpress"
  password          = "wordpress"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }
  enabled = true
  default_root_object = "index.html"
  aliases = ["${var.project_name}.com"]
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
      locations        = ["US", "CA", "GB", "DE"]
    }
  }
  tags = {
    Name        = "${var.project_name}-cfd"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Create S3 bucket
resource "aws_s3_bucket" "wordpress_s3" {
  bucket = "${var.project_name}.com"
  acl    = "public-read"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource = [
          aws_s3_bucket.wordpress_s3.arn,
          "${aws_s3_bucket.wordpress_s3.arn}/*",
        ]
      },
    ]
  })
  tags = {
    Name        = "${var.project_name}-s3"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Create Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_r53" {
  name = "${var.project_name}.com"
}

resource "aws_route53_record" "wordpress_r53_record" {
  zone_id = aws_route53_zone.wordpress_r53.zone_id
  name    = "${var.project_name}.com"
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id                = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "wordpress_cfd_record" {
  zone_id = aws_route53_zone.wordpress_r53.zone_id
  name    = "${var.project_name}.com"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cfd.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cfd.zone_id
    evaluate_target_health = false
  }
}

# Outputs
output "wordpress-elb-dns" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress-rds-endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "wordpress-s3-bucket" {
  value = aws_s3_bucket.wordpress_s3.bucket
}

output "wordpress-cfd-domain" {
  value = aws_cloudfront_distribution.wordpress_cfd.domain_name
}

output "wordpress-r53-zone-id" {
  value = aws_route53_zone.wordpress_r53.zone_id
}
