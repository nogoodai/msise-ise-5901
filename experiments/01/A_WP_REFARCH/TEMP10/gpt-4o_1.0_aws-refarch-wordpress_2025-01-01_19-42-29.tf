terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  default = "us-east-1"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

resource "aws_vpc" "wordpress" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress.id
  cidr_block        = element(var.public_subnet_cidrs, count.index)
  map_public_ip_on_launch = true
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "PublicSubnet-${count.index}"
  }
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "PrivateSubnet-${count.index}"
  }
}

resource "aws_internet_gateway" "wordpress" {
  vpc_id = aws_vpc.wordpress.id
  tags = {
    Name = "WordPressInternetGateway"
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
  count          = length(aws_subnet.public)
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_server" {
  vpc_id = aws_vpc.wordpress.id
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
    cidr_blocks = ["1.2.3.4/32"] # Replace with your IP
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "WebServerSG"
  }
}

resource "aws_security_group" "db" {
  vpc_id = aws_vpc.wordpress.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "DatabaseSG"
  }
}

resource "aws_instance" "bastion" {
  ami           = "ami-0abcdef1234567890" # Replace with real AMI ID
  instance_type = "t2.micro"
  subnet_id     = element(aws_subnet.public.*.id, 0)
  key_name      = var.key_name

  security_groups = [aws_security_group.web_server.id]

  associate_public_ip_address = true

  tags = {
    Name = "BastionHost"
  }
}

variable "key_name" {
  description = "SSH key for bastion access"
}

resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
}

resource "aws_efs_file_system" "wordpress" {
  tags = {
    Name = "WordPressEFS"
  }
}

resource "aws_efs_mount_target" "wordpress" {
  count          = length(aws_subnet.private)
  file_system_id = aws_efs_file_system.wordpress.id
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  security_groups = [aws_security_group.web_server.id]
}

resource "aws_elasticache_cluster" "wordpress_cache" {
  cluster_id           = "wordpress-cache"
  engine               = "redis"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  subnet_group_name    = aws_elasticache_subnet_group.wordpress.name
  security_group_ids   = [aws_security_group.web_server.id]
  parameter_group_name = "default.redis3.2"
}

resource "aws_elasticache_subnet_group" "wordpress" {
  name       = "wordpress-cache-subnet-group"
  subnet_ids = aws_subnet.private.*.id
}

resource "aws_elb" "wordpress" {
  name               = "wordpress-lb"
  availability_zones = data.aws_availability_zones.available.names
  security_groups    = [aws_security_group.web_server.id]

  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  listener {
    instance_port     = 443
    instance_protocol = "HTTPS"
    lb_port           = 443
    lb_protocol       = "HTTPS"
    ssl_certificate_id = var.ssl_certificate_id # Replace with actual certificate
  }

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "WordPressLoadBalancer"
  }
}

variable "ssl_certificate_id" {
  description = "SSL certificate for HTTPS listener"
}

resource "aws_autoscaling_group" "wordpress" {
  desired_capacity     = 2
  max_size             = 5
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.private.*.id
  launch_configuration = aws_launch_configuration.wordpress.id
}

resource "aws_launch_configuration" "wordpress" {
  name          = "wordpress-launch-configuration"
  image_id      = "ami-0abcdef1234567890" # Replace with real AMI ID
  instance_type = "t2.micro"
  key_name      = var.key_name

  security_groups = [aws_security_group.web_server.id]

  user_data = file("wordpress_install.sh")

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "wordpress" {
  identifier             = "wordpress-db"
  instance_class         = "db.t2.small"
  engine                 = "mysql"
  engine_version         = "5.7"
  allocated_storage      = 20
  username               = "wpadmin"
  password               = "wpadminpassword" # Update with a secure password
  vpc_security_group_ids = [aws_security_group.db.id]
  db_subnet_group_name   = aws_db_subnet_group.wordpress.name
  multi_az               = true
  parameter_group_name   = "default.mysql5.7"

  tags = {
    Name = "WordPressDB"
  }
}

resource "aws_db_subnet_group" "wordpress" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private.*.id
}

resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_s3_bucket.wordpress_bucket.bucket_regional_domain_name
    origin_id   = "s3-wordpress-origin"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.wordpress.id
    }
  }

  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    target_origin_id       = "s3-wordpress-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "blacklist"
      locations        = ["CN"]
    }
  }

  viewer_certificate {
    acm_certificate_arn            = var.ssl_certificate_id
    ssl_support_method             = "sni-only"
  }

  tags = {
    Name = "WordPressCloudFront"
  }
}

resource "aws_cloudfront_origin_access_identity" "wordpress" {
  comment = "Allows CloudFront to access S3 bucket"
}

resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-static-assets"
  acl    = "private"

  tags = {
    Name = "WordPressStaticAssets"
  }
}

resource "aws_route53_zone" "wordpress" {
  name = "example.com." # Replace with your domain
}

resource "aws_route53_record" "alias" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = "www.example.com" # Replace with your domain
  type    = "A"
  
  alias {
    name                   = aws_cloudfront_distribution.wordpress.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress.hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_cloudwatch_dashboard" "wordpress" {
  dashboard_name = "WordPressDashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        x    = 0
        y    = 0
        width = 6
        height = 4
        properties = {
          metrics = [
            [ "AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.bastion.id ]
          ]
          view = "timeSeries"
          stacked = false
          region = var.region
          period = 300
          stat = "Average"
        }
      }
    ]
  })
}

data "aws_availability_zones" "available" {}

output "elb_dns_name" {
  value = aws_elb.wordpress.dns_name
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress.endpoint
}
