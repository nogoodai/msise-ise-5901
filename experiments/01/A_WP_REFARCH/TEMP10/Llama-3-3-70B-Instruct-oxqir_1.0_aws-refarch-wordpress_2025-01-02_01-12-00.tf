provider "aws" {
  region = "us-west-2"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  default = ["us-west-2a", "us-west-2b"]
}

variable "instance_type" {
  default = "t2.micro"
}

variable "wordpress_version" {
  default = "latest"
}

variable "rds_instance_class" {
  default = "db.t2.micro"
}

variable "mysql_version" {
  default = "8.0"
}

variable "zone_name" {
  default = "example.com"
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "WordPressIGW"
  }
}

resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "WordPressPublicSubnet-${count.index}"
  }
}

resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, length(var.availability_zones) + count.index)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "WordPressPrivateSubnet-${count.index}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "WordPressPublicRouteTable"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "WordPressPrivateRouteTable"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "web" {
  name        = "wordpress-web-sg"
  description = "Allow HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.main.id

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
    Name = "WordPressWebSG"
  }
}

resource "aws_security_group" "rds" {
  name        = "wordpress-rds-sg"
  description = "Allow MySQL traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
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

resource "aws_instance" "web" {
  count = 2

  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.web.id]
  subnet_id = aws_subnet.public[count.index].id
  key_name               = "wordpress-key"
  user_data = file("${path.module}/scripts/install_wordpress.sh")

  tags = {
    Name = "WordPressWebServer-${count.index}"
  }
}

resource "aws_db_instance" "main" {
  identifier        = "wordpress-rds"
  engine            = "mysql"
  engine_version    = var.mysql_version
  instance_class    = var.rds_instance_class
  multi_az          = true
  storage_type      = "gp2"
  allocated_storage = 20
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.id
  parameter_group_name = aws_db_parameter_group.main.id
  username             = "wordpress"
  password             = "wordpress"
}

resource "aws_db_parameter_group" "main" {
  name        = "wordpress-rds-pg"
  family      = "mysql5.7"
  description = "RDS parameter group for WordPress"

  parameter {
    name  = "character_set_server"
    value = "utf8"
  }

  parameter {
    name  = "character_set_client"
    value = "utf8"
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "wordpress-rds-sg"
  subnet_ids = aws_subnet.private.*.id
}

resource "aws_elasticache_cluster" "main" {
  cluster_id           = "wordpress-ec"
  engine               = "memcached"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 2
  parameter_group_name = "default.memcached1.6"
  port                 = 11211
  security_group_ids   = [aws_security_group.web.id]
  subnet_group_name    = aws_elasticache_subnet_group.main.id
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "wordpress-ec-sg"
  description = "Elasticache subnet group for WordPress"
  subnet_ids = aws_subnet.private.*.id
}

resource "aws_elb" "main" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.public.*.id
  security_groups = [aws_security_group.web.id]

  listener {
    lb_port       = 80
    lb_protocol   = "http"
    instance_port = 80
    instance_protocol = "http"
  }

  listener {
    lb_port       = 443
    lb_protocol   = "https"
    instance_port = 80
    instance_protocol = "http"
    ssl_certificate_id = "arn:aws:iam::123456789012:server-certificate/WordPressCert"
  }

  tags = {
    Name = "WordPressELB"
  }
}

resource "aws_autoscaling_group" "main" {
  name                 = "wordpress-asg"
  max_size             = 3
  min_size             = 1
  desired_capacity     = 2
  health_check_type    = "ELB"
  launch_configuration = aws_launch_configuration.main.name
  load_balancers       = [aws_elb.main.id]

  vpc_zone_identifier = aws_subnet.public.*.id

  tags = [
    {
      key                 = "Name"
      value               = "WordPressASG"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = "Production"
      propagate_at_launch = true
    },
  ]
}

resource "aws_launch_configuration" "main" {
  name          = "wordpress-lc"
  image_id      = "ami-0c55b159cbfafe1f0"
  instance_type = var.instance_type
  security_groups = [aws_security_group.web.id]
  key_name               = "wordpress-key"
  user_data = file("${path.module}/scripts/install_wordpress.sh")

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudfront_distribution" "main" {
  origin {
    domain_name = aws_elb.main.dns_name
    origin_id   = "WordPressELB"

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "match-viewer"
      origin_ssl_protocols      = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }

  enabled = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WordPressELB"

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

  tags = {
    Name = "WordPressCloudFrontDistribution"
  }
}

resource "aws_s3_bucket" "main" {
  bucket = "wordpress-static-assets"
  acl    = "private"

  versioning {
    enabled = true
  }

  tagging = {
    Environment = "Production"
  }
}

resource "aws_route53_zone" "main" {
  name = var.zone_name
}

resource "aws_route53_record" "main" {
  zone_id = aws_route53_zone.main.id
  name    = var.zone_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id               = aws_cloudfront_distribution.main.zone_id
    evaluate_target_health = false
  }
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "elb_dns_name" {
  value = aws_elb.main.dns_name
}

output "cloudfront_distribution_domain" {
  value = aws_cloudfront_distribution.main.domain_name
}

output "rds_instance_address" {
  value = aws_db_instance.main.address
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.main.arn
}

output "route53_zone_id" {
  value = aws_route53_zone.main.id
}
