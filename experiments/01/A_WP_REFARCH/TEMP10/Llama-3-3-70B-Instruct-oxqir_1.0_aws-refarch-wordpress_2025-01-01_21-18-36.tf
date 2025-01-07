provider "aws" {
  region = "us-west-2"
  version = "5.1.0"
}

variable "wordpress_vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "wordpress_vpc_name" {
  default = "WordPressVPC"
}

variable "wordpress_availability_zones" {
  default = ["us-west-2a", "us-west-2b"]
}

variable "wordpress_ec2_instance_type" {
  default = "t2.micro"
}

variable "wordpress_rds_instance_type" {
  default = "db.t2.small"
}

variable "wordpress_elasticache_instance_type" {
  default = "cache.t2.micro"
}

variable "wordpress_key_pair_name" {
  default = "wordpress-ssh-key"
}

variable "wordpress_bastion_instance_type" {
  default = "t2.micro"
}

# VPC Configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.wordpress_vpc_cidr
  tags = {
    Name = var.wordpress_vpc_name
  }
}

# Subnets Configuration
resource "aws_subnet" "wordpress_public_subnet_1" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = var.wordpress_availability_zones[0]
  tags = {
    Name = "WordPressPublicSubnet1"
  }
}

resource "aws_subnet" "wordpress_public_subnet_2" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = var.wordpress_availability_zones[1]
  tags = {
    Name = "WordPressPublicSubnet2"
  }
}

resource "aws_subnet" "wordpress_private_subnet_1" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = var.wordpress_availability_zones[0]
  tags = {
    Name = "WordPressPrivateSubnet1"
  }
}

resource "aws_subnet" "wordpress_private_subnet_2" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = var.wordpress_availability_zones[1]
  tags = {
    Name = "WordPressPrivateSubnet2"
  }
}

# Internet Gateway Configuration
resource "aws_internet_gateway" "wordpress_internet_gateway" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressInternetGateway"
  }
}

# Route Tables Configuration
resource "aws_route_table" "wordpress_public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressPublicRouteTable"
  }
}

resource "aws_route" "wordpress_public_route" {
  route_table_id         = aws_route_table.wordpress_public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_internet_gateway.id
}

resource "aws_route_table_association" "wordpress_public_subnet_1_association" {
  subnet_id      = aws_subnet.wordpress_public_subnet_1.id
  route_table_id = aws_route_table.wordpress_public_route_table.id
}

resource "aws_route_table_association" "wordpress_public_subnet_2_association" {
  subnet_id      = aws_subnet.wordpress_public_subnet_2.id
  route_table_id = aws_route_table.wordpress_public_route_table.id
}

resource "aws_route_table" "wordpress_private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressPrivateRouteTable"
  }
}

resource "aws_route_table_association" "wordpress_private_subnet_1_association" {
  subnet_id      = aws_subnet.wordpress_private_subnet_1.id
  route_table_id = aws_route_table.wordpress_private_route_table.id
}

resource "aws_route_table_association" "wordpress_private_subnet_2_association" {
  subnet_id      = aws_subnet.wordpress_private_subnet_2.id
  route_table_id = aws_route_table.wordpress_private_route_table.id
}

# Security Group Configuration
resource "aws_security_group" "wordpress_ec2_security_group" {
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
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
    Name = "WordPressEC2SecurityGroup"
  }
}

resource "aws_security_group" "wordpress_rds_security_group" {
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_ec2_security_group.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "WordPressRDSSecurityGroup"
  }
}

# EC2 Configuration
resource "aws_instance" "wordpress_bastion" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.wordpress_bastion_instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_ec2_security_group.id]
  subnet_id = aws_subnet.wordpress_public_subnet_1.id
  key_name = var.wordpress_key_pair_name
  tags = {
    Name = "WordPressBastion"
  }
}

# RDS Configuration
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = var.wordpress_rds_instance_type
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password123"
  vpc_security_group_ids = [aws_security_group.wordpress_rds_security_group.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  tags = {
    Name = "WordPressRDS"
  }
}

# DB Subnet Group Configuration
resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = [aws_subnet.wordpress_private_subnet_1.id, aws_subnet.wordpress_private_subnet_2.id]
  tags = {
    Name = "WordPressRDSSubnetGroup"
  }
}

# Elasticache Configuration
resource "aws_elasticache_cluster" "wordpress_elasticache" {
  cluster_id           = "wordpress-elasticache"
  engine               = "memcached"
  node_type            = var.wordpress_elasticache_instance_type
  num_cache_nodes      = 1
  parameter_group_name = "default.memcached1.6"
  port                 = 11211
  security_group_ids   = [aws_security_group.wordpress_ec2_security_group.id]
  tags = {
    Name = "WordPressElasticache"
  }
}

# Elastic Load Balancer Configuration
resource "aws_lb" "wordpress_elb" {
  name               = "wordpress-elb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.wordpress_ec2_security_group.id]
  subnets            = [aws_subnet.wordpress_public_subnet_1.id, aws_subnet.wordpress_public_subnet_2.id]
  tags = {
    Name = "WordPressELB"
  }
}

# Target Group Configuration
resource "aws_lb_target_group" "wordpress_target_group" {
  name     = "wordpress-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressTargetGroup"
  }
}

# Auto Scaling Configuration
resource "aws_autoscaling_group" "wordpress_autoscaling_group" {
  name                      = "wordpress-autoscaling-group"
  max_size                  = 3
  min_size                  = 1
  desired_capacity          = 2
  health_check_grace_period = 300
  health_check_type         = "EC2"
  launch_configuration      = aws_launch_configuration.wordpress_launch_configuration.name
  vpc_zone_identifier       = [aws_subnet.wordpress_private_subnet_1.id, aws_subnet.wordpress_private_subnet_2.id]
  tags = [
    {
      key                 = "Name"
      value               = "WordPressEC2Instance"
      propagate_at_launch = true
    },
  ]
}

# Launch Configuration
resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name          = "wordpress-launch-configuration"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.wordpress_ec2_instance_type
  security_groups = [aws_security_group.wordpress_ec2_security_group.id]
  user_data = file("${path.module}/wordpress-install.sh")
}

# CloudFront Configuration
resource "aws_cloudfront_distribution" "wordpress_cloudfront" {
  enabled = true
  origin {
    domain_name = aws_lb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }
  aliases = ["example.com"]
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
    min_ttl                = 3600
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "sni-only"
  }
  tags = {
    Name = "WordPressCloudFront"
  }
}

# S3 Configuration
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = "wordpress-s3-bucket"
  acl    = "private"
  tags = {
    Name = "WordPressS3Bucket"
  }
}

# Route 53 Configuration
resource "aws_route53_zone" "wordpress_route53_zone" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name    = "example.com"
  type    = "A"
  alias {
    name                   = aws_lb.wordpress_elb.dns_name
    zone_id               = aws_lb.wordpress_elb.zone_id
    evaluate_target_health = true
  }
}
