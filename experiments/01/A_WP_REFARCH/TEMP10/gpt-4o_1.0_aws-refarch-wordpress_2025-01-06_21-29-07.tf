terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources in"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "allowed_ssh_ips" {
  description = "IP addresses allowed to SSH into instances"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "wordpress_instance_type" {
  description = "The instance type for WordPress EC2 instances"
  default     = "t2.micro"
}

variable "db_instance_class" {
  description = "The instance class for the RDS database"
  default     = "db.t2.small"
}

variable "project_tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {
    Project     = "WordPressDeployment"
    Environment = "Production"
  }
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = merge(var.project_tags, {
    Name = "WordPressVPC"
  })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = merge(var.project_tags, {
    Name = "WordPressIGW"
  })
}

resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = merge(var.project_tags, {
    Name = "WordPressPublicSubnet-${count.index}"
  })
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = merge(var.project_tags, {
    Name = "WordPressPrivateSubnet-${count.index}"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = merge(var.project_tags, {
    Name = "WordPressPublicRT"
  })
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = merge(var.project_tags, {
    Name = "WordPressWebSG"
  })

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
    cidr_blocks = var.allowed_ssh_ips
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = merge(var.project_tags, {
    Name = "WordPressDBSG"
  })

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public[0].id
  associate_public_ip_address = true
  key_name               = var.ssh_key_name
  tags = merge(var.project_tags, {
    Name = "WordPressBastion"
  })

  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_key_pair" "bastion" {
  key_name   = var.ssh_key_name
  public_key = var.ssh_public_key
}

resource "aws_autoscaling_group" "wordpress_asg" {
  min_size             = 1
  max_size             = 3
  desired_capacity     = 2
  vpc_zone_identifier  = aws_subnet.public[*].id

  launch_configuration = aws_launch_configuration.wordpress.id

  tags = [
    {
      key                 = "Name"
      value               = "WordPressInstance"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.wordpress_instance_type
  security_groups             = [aws_security_group.web_sg.id]
  user_data                   = file("wordpress-user-data.sh")
  associate_public_ip_address = true
  key_name                    = var.ssh_key_name
}

resource "aws_elb" "wordpress" {
  name               = "WordPressLoadBalancer"
  availability_zones = data.aws_availability_zones.available.names

  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  listener {
    instance_port      = 443
    instance_protocol  = "HTTPS"
    lb_port            = 443
    lb_protocol        = "HTTPS"
    ssl_certificate_id = var.ssl_certificate_arn
  }

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  instances                   = aws_autoscaling_group.wordpress_asg.instances
  security_groups             = [aws_security_group.web_sg.id]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 300

  tags = merge(var.project_tags, {
    Name = "WordPressLB"
  })
}

resource "aws_rds_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  instance_class       = var.db_instance_class
  name                 = "wordpress"
  username             = "admin"
  password             = random_password.db.password
  db_subnet_group_name = aws_db_subnet_group.db_subnet.id
  multi_az             = true
  storage_type         = "gp2"
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  tags = merge(var.project_tags, {
    Name = "WordPressDB"
  })
}

resource "aws_db_subnet_group" "db_subnet" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = merge(var.project_tags, {
    Name = "WordPressDBSubnetGroup"
  })
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket_prefix = "wordpress-assets-"
  acl           = "public-read"

  tags = merge(var.project_tags, {
    Name = "WordPressAssets"
  })
}

resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "S3-WordPressAssets"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "WordPress CloudFront Distribution"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-WordPressAssets"

    forward_cookie {
      forward = "none"
    }

    viewer_protocol_policy = "redirect-to-https"
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
    cloudfront_default_certificate = true
  }

  tags = merge(var.project_tags, {
    Name = "WordPressCloudFront"
  })
}

resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name

  tags = merge(var.project_tags, {
    Name = "WordPressRoute53"
  })
}

resource "aws_route53_record" "wordpress_alb" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_elb.wordpress.dns_name
    zone_id                = aws_elb.wordpress.zone_id
    evaluate_target_health = true
  }
}

output "wordpress_vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "wordpress_public_subnets" {
  value = aws_subnet.public[*].id
}

output "wordpress_private_subnets" {
  value = aws_subnet.private[*].id
}

output "wordpress_elb_dns" {
  value = aws_elb.wordpress.dns_name
}

output "wordpress_rds_endpoint" {
  value = aws_rds_instance.wordpress_db.endpoint
}

output "wordpress_cloudfront_domain" {
  value = aws_cloudfront_distribution.wordpress.domain_name
}
