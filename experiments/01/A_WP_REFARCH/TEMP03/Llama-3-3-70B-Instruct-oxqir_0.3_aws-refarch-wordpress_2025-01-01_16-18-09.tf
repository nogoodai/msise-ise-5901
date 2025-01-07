provider "aws" {
  region = "us-west-2"
  version = "5.1.0"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  default = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "instance_type" {
  default = "t2.micro"
}

variable "ami_id" {
  default = "ami-0c94855ba95c71c99"
}

variable "database_instance_class" {
  default = "db.t2.small"
}

variable "database_username" {
  default = "wordpressuser"
}

variable "database_password" {
  default = "wordpresspassword"
}

variable "domain_name" {
  default = "example.com"
}

variable "cloudfront_ssl_certificate" {
  default = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
}

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

resource "aws_subnet" "public_subnets" {
  count = length(var.availability_zones)
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "WordPressPublicSubnet${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count = length(var.availability_zones)
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, length(var.availability_zones) + count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "WordPressPrivateSubnet${count.index + 1}"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressPublicRouteTable"
  }
}

resource "aws_route" "public_route" {
  route_table_id = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table_association" "public_route_table_association" {
  count = length(var.availability_zones)
  subnet_id = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_security_group" "web_server_security_group" {
  name        = "WordPressWebServerSecurityGroup"
  description = "Allow inbound HTTP and HTTPS traffic"
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
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WordPressWebServerSecurityGroup"
  }
}

resource "aws_security_group" "database_security_group" {
  name        = "WordPressDatabaseSecurityGroup"
  description = "Allow inbound MySQL traffic from web server"
  vpc_id      = aws_vpc.wordpress_vpc.id

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
    Name = "WordPressDatabaseSecurityGroup"
  }
}

resource "aws_instance" "wordpress_instance" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.web_server_security_group.id]
  subnet_id = aws_subnet.public_subnets[0].id
  key_name               = "wordpress-key"
  tags = {
    Name = "WordPressInstance"
  }
}

resource "aws_db_instance" "wordpress_database" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = var.database_instance_class
  name                 = "wordpressdb"
  username             = var.database_username
  password             = var.database_password
  vpc_security_group_ids = [aws_security_group.database_security_group.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  skip_final_snapshot  = true
  tags = {
    Name = "WordPressDatabase"
  }
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private_subnets.*.id

  tags = {
    Name = "WordPressDBSubnetGroup"
  }
}

resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.web_server_security_group.id]

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

resource "aws_autoscaling_group" "wordpress_autoscaling_group" {
  name                      = "wordpress-autoscaling-group"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity          = 1
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_launch_configuration.name
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id

  tag {
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name          = "wordpress-launch-configuration"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_server_security_group.id]
  key_name               = "wordpress-key"
  user_data = file("${path.module}/user_data.sh")

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudfront_distribution" "wordpress_cloudfront_distribution" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }

  enabled = true

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
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = var.cloudfront_ssl_certificate
    ssl_support_method  = "sni-only"
  }
}

resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = "wordpress-s3-bucket"
  acl    = "private"

  tags = {
    Name        = "WordPressS3Bucket"
    Environment = "production"
  }
}

resource "aws_route53_zone" "wordpress_route53_zone" {
  name = var.domain_name
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cloudfront_distribution.zone_id
    evaluate_target_health = false
  }
}

output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
}

output "wordpress_route53_zone_id" {
  value = aws_route53_zone.wordpress_route53_zone.zone_id
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3_bucket.bucket
}
