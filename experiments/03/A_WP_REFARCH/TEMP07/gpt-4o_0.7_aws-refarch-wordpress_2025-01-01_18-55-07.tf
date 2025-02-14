terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy to."
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet."
  default     = ["10.0.1.0/24"]
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet."
  default     = ["10.0.2.0/24"]
}

variable "ami_id" {
  description = "AMI ID for the EC2 instances."
  default     = "ami-04505e74c0741db8d" # Replace with actual AMI ID
}

variable "instance_type" {
  description = "EC2 instance type for WordPress."
  default     = "t2.micro"
}

variable "key_name" {
  description = "Key pair for SSH access."
  default     = "my-key-pair" # Replace with your key pair name
}

resource "aws_vpc" "wordpress" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidr)
  vpc_id = aws_vpc.wordpress.id
  cidr_block = var.public_subnet_cidr[count.index]
  map_public_ip_on_launch = true
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name = "PublicSubnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidr)
  vpc_id = aws_vpc.wordpress.id
  cidr_block = var.private_subnet_cidr[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name = "PrivateSubnet-${count.index + 1}"
  }
}

resource "aws_internet_gateway" "wordpress" {
  vpc_id = aws_vpc.wordpress.id
  tags = {
    Name = "WordPressIGW"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress.id
  }

  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidr)
  subnet_id = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress.id
  description = "Security group for web tier"

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["your-ip-here/32"] # Replace with your IP
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WebServerSG"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress.id
  description = "Security group for database"

  ingress {
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "DatabaseSG"
  }
}

resource "aws_instance" "bastion" {
  ami = var.ami_id
  instance_type = var.instance_type
  key_name = var.key_name
  subnet_id = aws_subnet.public[0].id
  security_groups = [aws_security_group.web_sg.id]
  associate_public_ip_address = true

  tags = {
    Name = "BastionHost"
  }
}

resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion.id
  vpc = true
}

resource "aws_elb" "wordpress" {
  name = "wordpress-elb"
  availability_zones = data.aws_availability_zones.available.names
  security_groups = [aws_security_group.web_sg.id]

  listener {
    instance_port = 80
    instance_protocol = "HTTP"
    lb_port = 80
    lb_protocol = "HTTP"
  }

  listener {
    instance_port = 443
    instance_protocol = "HTTPS"
    lb_port = 443
    lb_protocol = "HTTPS"
    ssl_certificate_id = "arn:aws:acm:region:account:certificate/12345678-abcd-1234-abcd-12345678abcd" # Replace with your certificate ARN
  }

  health_check {
    target = "HTTP:80/"
    interval = 30
    timeout = 5
    healthy_threshold = 2
    unhealthy_threshold = 2
  }

  instances = [aws_instance.bastion.id]

  tags = {
    Name = "WordPressELB"
  }
}

resource "aws_db_instance" "wordpress" {
  allocated_storage = 20
  engine = "mysql"
  instance_class = "db.t2.micro"
  name = "wordpressdb"
  username = "admin"
  password = "password" # Update with a secure password
  parameter_group_name = "default.mysql8.0"
  multi_az = true
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  skip_final_snapshot = true

  tags = {
    Name = "WordPressDB"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  desired_capacity = 2
  max_size = 5
  min_size = 1
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns = [aws_lb_target_group.wordpress.id]

  launch_configuration = aws_launch_configuration.wordpress_lc.id

  tag {
    key = "Name"
    value = "WordPressInstance"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress_lc" {
  name_prefix = "wordpress-lc-"
  image_id = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_sg.id]
  key_name = var.key_name
  user_data = file("path/to/your/user-data.sh") # Replace with your user data script

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_s3_bucket.static_website.bucket_regional_domain_name
    origin_id = "S3-origin"
  }

  enabled = true
  is_ipv6_enabled = true
  comment = "CloudFront Distribution for WordPress"

  default_cache_behavior {
    allowed_methods = ["GET", "HEAD"]
    cached_methods = ["GET", "HEAD"]
    target_origin_id = "S3-origin"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "redirect-to-https"
  }

  viewer_certificate {
    acm_certificate_arn = "arn:aws:acm:region:account:certificate/12345678-abcd-1234-abcd-12345678abcd" # Replace with your certificate ARN
    ssl_support_method = "sni-only"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "WordPressCloudFront"
  }
}

resource "aws_s3_bucket" "static_website" {
  bucket = "wordpress-static-assets"
  acl    = "private"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid = "PublicReadGetObject",
        Effect = "Allow",
        Principal = "*",
        Action = "s3:GetObject",
        Resource = "arn:aws:s3:::${self.bucket}/*"
      }
    ]
  })

  tags = {
    Name = "WordPressStaticAssets"
  }
}

resource "aws_route53_zone" "wordpress" {
  name = "example.com" # Replace with your domain
}

resource "aws_route53_record" "wordpress" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name = "www.example.com" # Replace with your domain
  type = "A"
  alias {
    name = aws_cloudfront_distribution.wordpress.domain_name
    zone_id = aws_cloudfront_distribution.wordpress.hosted_zone_id
    evaluate_target_health = false
  }
}

data "aws_availability_zones" "available" {}

output "vpc_id" {
  value = aws_vpc.wordpress.id
}

output "elb_dns_name" {
  value = aws_elb.wordpress.dns_name
}

output "db_endpoint" {
  value = aws_db_instance.wordpress.endpoint
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress.domain_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.static_website.id
}
