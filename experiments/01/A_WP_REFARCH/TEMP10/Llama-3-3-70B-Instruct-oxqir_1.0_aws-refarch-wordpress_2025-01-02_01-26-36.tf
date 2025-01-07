# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-west-2"
}

# VPC Configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
  }
}

# Public Subnet Configuration
resource "aws_subnet" "public_subnet" {
  count = 2

  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, count.index)
  availability_zone = "us-west-2${count.index + 1}"
  map_public_ip_on_launch = true

  tags = {
    Name        = "PublicSubnet${count.index + 1}"
    Environment = "production"
  }
}

# Private Subnet Configuration
resource "aws_subnet" "private_subnet" {
  count = 2

  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, count.index + 2)
  availability_zone = "us-west-2${count.index + 1}"

  tags = {
    Name        = "PrivateSubnet${count.index + 1}"
    Environment = "production"
  }
}

# Internet Gateway Configuration
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
  }
}

# Public Route Table Configuration
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }

  tags = {
    Name        = "PublicRouteTable"
    Environment = "production"
  }
}

# Private Route Table Configuration
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "PrivateRouteTable"
    Environment = "production"
  }
}

# Route Table Association
resource "aws_route_table_association" "public_route_table_association" {
  count = 2

  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_route_table_association" {
  count = 2

  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security Group Configuration
resource "aws_security_group" "wordpress_web_server_sg" {
  name        = "WordPressWebServerSG"
  description = "Security group for WordPress web server"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "Allow HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow SSH traffic"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["192.168.1.0/24"]
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

resource "aws_security_group" "wordpress_db_sg" {
  name        = "WordPressDBSG"
  description = "Security group for WordPress database"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description     = "Allow MySQL traffic"
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
    Name        = "WordPressDBSG"
    Environment = "production"
  }
}

# EC2 Instance Configuration
resource "aws_instance" "wordpress_web_server" {
  ami           = "ami-abcd1234"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnet[0].id
  vpc_security_group_ids = [aws_security_group.wordpress_web_server_sg.id]

  tags = {
    Name        = "WordPressWebServer"
    Environment = "production"
  }
}

# RDS Instance Configuration
resource "aws_db_instance" "wordpress_db" {
  engine               = "mysql"
  instance_class      = "db.t2.micro"
  allocated_storage    = 20
  storage_type         = "gp2"
  name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = "wordpresspassword"
  vpc_security_group_ids = [aws_security_group.wordpress_db_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  multi_az             = true
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress_db_subnet_group"
  subnet_ids = aws_subnet.private_subnet.*.id

  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = "production"
  }
}

# Elastic Load Balancer Configuration
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.public_subnet.*.id
  security_groups = [aws_security_group.wordpress_web_server_sg.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  tags = {
    Name        = "WordPressELB"
    Environment = "production"
  }
}

# Auto Scaling Group Configuration
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "ELB"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_launch_config.name

  vpc_zone_identifier = aws_subnet.public_subnet.*.id

  tag {
    key                 = "Name"
    value               = "WordPressASG"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "production"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress_launch_config" {
  name          = "wordpress-launch-config"
  image_id      = "ami-abcd1234"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.wordpress_web_server_sg.id]
}

# CloudFront Distribution Configuration
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }

  enabled = true
  is_ipv6_enabled = true

  default_cache_behavior {
    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]
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
    cloudfront_default_certificate = true
  }
}

# S3 Bucket Configuration
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = "wordpress-s3-bucket"
  acl    = "private"

  tags = {
    Name        = "WordPressS3Bucket"
    Environment = "production"
  }
}

# Route 53 Configuration
resource "aws_route53_zone" "wordpress_route53_zone" {
  name = "example.com"

  tags = {
    Name        = "WordPressRoute53Zone"
    Environment = "production"
  }
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.zone_id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cfd.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cfd.zone_id
    evaluate_target_health = false
  }
}
