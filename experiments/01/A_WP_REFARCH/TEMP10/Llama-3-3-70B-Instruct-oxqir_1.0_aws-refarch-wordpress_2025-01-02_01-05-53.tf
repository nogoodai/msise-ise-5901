provider "aws" {
  region = "us-west-2"
}

variable "cidr_block" {
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  default = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "instance_type" {
  default = "t2.micro"
}

variable "ami" {
  default = "ami-0c55b159cbfafe1f0"
}

variable "rds_instance_class" {
  default = "db.t2.small"
}

variable "cloudfront_origin_path" {
  default = ""
}

variable "cloudfront_ssl_certificate" {
  default = "arn:aws:iam::123456789012:server-certificate/WordPress-Site-SSL"
}

variable "route53_zone_id" {
  default = "Z0123456789ABCDEF"
}

variable "wordpress_key_pair_name" {
  default = "wordpress-key-pair"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.cidr_block
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_subnet" "wordpress_public_subnet" {
  count             = 3
  cidr_block        = cidrsubnet(var.cidr_block, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressPublicSubnet${count.index + 1}"
  }
}

resource "aws_subnet" "wordpress_private_subnet" {
  count             = 3
  cidr_block        = cidrsubnet(var.cidr_block, 8, count.index + 3)
  availability_zone = var.availability_zones[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressPrivateSubnet${count.index + 1}"
  }
}

resource "aws_internet_gateway" "wordpress_internet_gateway" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressInternetGateway"
  }
}

resource "aws_route_table" "wordpress_public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_internet_gateway.id
  }
  tags = {
    Name = "WordPressPublicRouteTable"
  }
}

resource "aws_route_table_association" "wordpress_public_subnet_association" {
  count          = 3
  subnet_id      = aws_subnet.wordpress_public_subnet[count.index].id
  route_table_id = aws_route_table.wordpress_public_route_table.id
}

resource "aws_security_group" "wordpress_web_server_sg" {
  name        = "WordPressWebServerSG"
  description = "Allow HTTP, HTTPS and SSH"
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
    Name = "WordPressWebServerSG"
  }
}

resource "aws_security_group" "wordpress_rds_sg" {
  name        = "WordPressRDSSG"
  description = "Allow MySQL"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_web_server_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "WordPressRDSSG"
  }
}

resource "aws_instance" "wordpress_web_server" {
  ami           = var.ami
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.wordpress_web_server_sg.id
  ]
  subnet_id = aws_subnet.wordpress_private_subnet[0].id
  tags = {
    Name = "WordPressWebServer"
  }
}

resource "aws_db_instance" "wordpress_rds" {
  identifier           = "wordpress-rds"
  instance_class       = var.rds_instance_class
  engine               = "mysql"
  engine_version       = "8.0.28"
  db_name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = "wordpresspassword"
  vpc_security_group_ids = [
    aws_security_group.wordpress_rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  storage_type         = "gp2"
  allocated_storage    = 20
  skip_final_snapshot  = true
  multi_az             = true
  tags = {
    Name = "WordPressRDS"
  }
}

resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = aws_subnet.wordpress_private_subnet[*].id
  tags = {
    Name = "WordPressRDSSubnetGroup"
  }
}

resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.wordpress_public_subnet[*].id
  security_groups = [aws_security_group.wordpress_web_server_sg.id]
  listener {
    lb_port       = 80
    lb_protocol   = "http"
    instance_port = 80
    instance_protocol = "http"
  }
  listener {
    lb_port       = 443
    lb_protocol   = "https"
    instance_port = 443
    instance_protocol = "https"
    ssl_certificate_id = var.cloudfront_ssl_certificate
  }
  tags = {
    Name = "WordPressELB"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  name                 = "wordpress-asg"
  max_size             = 5
  min_size             = 1
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier  = aws_subnet.wordpress_private_subnet[0].id
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
  image_id      = var.ami
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.wordpress_web_server_sg.id
  ]
  user_data = file("wordpress-user-data.sh")
}

resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-origin"
  }
  enabled = true
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-origin"
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

resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-bucket"
  acl    = "private"
  tags = {
    Name = "WordPressBucket"
  }
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = var.route53_zone_id
  name    = "wordpress.example.com"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cdn.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cdn.zone_id
    evaluate_target_health = false
  }
}

output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cdn.domain_name
}

output "wordpress_rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_bucket.id
}

output "wordpress_route53_record_name" {
  value = aws_route53_record.wordpress_record.name
}
