# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Specify provider version and region
provider "aws" {
  region = "us-west-2"
}

# VPC Configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "WordPressVPC"
    Environment = "Production"
    Project     = "WordPressInfrastructure"
  }
}

# Subnet Configuration
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-west-2a"
  map_public_ip_on_launch = true
  tags = {
    Name        = "PublicSubnet"
    Environment = "Production"
    Project     = "WordPressInfrastructure"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2b"
  tags = {
    Name        = "PrivateSubnet"
    Environment = "Production"
    Project     = "WordPressInfrastructure"
  }
}

# Internet Gateway Configuration
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "Production"
    Project     = "WordPressInfrastructure"
  }
}

# Route Table Configuration
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name        = "PublicRouteTable"
    Environment = "Production"
    Project     = "WordPressInfrastructure"
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }
  tags = {
    Name        = "PrivateRouteTable"
    Environment = "Production"
    Project     = "WordPressInfrastructure"
  }
}

resource "aws_route_table_association" "private_subnet_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

# NAT Gateway Configuration
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id
  depends_on    = [aws_internet_gateway.wordpress_igw]
}

resource "aws_eip" "nat_eip" {
  vpc = true
}

# Security Groups
resource "aws_security_group" "wordpress_sg" {
  name        = "WordPressSG"
  description = "Allow inbound HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WordPressSG"
    Environment = "Production"
    Project     = "WordPressInfrastructure"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "RDSSG"
  description = "Allow inbound MySQL traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    protocol        = "tcp"
    from_port       = 3306
    to_port         = 3306
    security_groups = [aws_security_group.wordpress_sg.id]
  }

  egress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "RDSSG"
    Environment = "Production"
    Project     = "WordPressInfrastructure"
  }
}

# EC2 Instances
resource "aws_instance" "wordpress_instance" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  subnet_id = aws_subnet.private_subnet.id
  key_name               = "wordpress_key"
  user_data = file("${path.module}/wordpress_install.sh")
  tags = {
    Name        = "WordPressInstance"
    Environment = "Production"
    Project     = "WordPressInfrastructure"
  }
}

# RDS Instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = "password123"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  deletion_protection  = false
  skip_final_snapshot  = true
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress_db_subnet_group"
  subnet_ids = [aws_subnet.private_subnet.id]

  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = "Production"
    Project     = "WordPressInfrastructure"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name               = "WordPressELB"
  subnets            = [aws_subnet.public_subnet.id]
  security_groups    = [aws_security_group.wordpress_sg.id]

  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 80
    lb_protocol        = "http"
  }

  tags = {
    Name        = "WordPressELB"
    Environment = "Production"
    Project     = "WordPressInfrastructure"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  max_size                  = 5
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_config.name
  vpc_zone_identifier       = aws_subnet.private_subnet.id
}

resource "aws_launch_configuration" "wordpress_config" {
  name          = "WordPressConfig"
  image_id      = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.wordpress_sg.id]
  key_name               = "wordpress_key"
  user_data = file("${path.module}/wordpress_install.sh")
  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "S3Origin"
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"

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

# S3 Bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-bucket"
  acl    = "private"

  tags = {
    Name        = "WordPressBucket"
    Environment = "Production"
    Project     = "WordPressInfrastructure"
  }
}

# Route 53 DNS Configuration
resource "aws_route53_record" "wordpress_dns" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "wordpress.example.com"
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
}

output "wordpress_dns_name" {
  value = aws_route53_record.wordpress_dns.name
}

output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}
