# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# VPC Configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Public Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name        = "PublicSubnet"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Private Subnet
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name        = "PrivateSubnet"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Public Route Table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Private Route Table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

# Public Route
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Security Groups
resource "aws_security_group" "wordpress_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  name        = "WordPressSG"
  description = "Allow inbound HTTP and HTTPS traffic"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["192.0.2.0/24"]
    description = "Allow HTTP traffic from specific IP range"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["192.0.2.0/24"]
    description = "Allow HTTPS traffic from specific IP range"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "WordPressSG"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  name        = "RDSSG"
  description = "Allow inbound MySQL traffic from WordPress instances"

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
    description     = "Allow MySQL traffic from WordPress instances"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "RDSSG"
    Environment = "production"
    Project     = "wordpress"
  }
}

# EC2 Instances for WordPress
resource "aws_instance" "wordpress_instance" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  subnet_id = aws_subnet.public_subnet.id
  key_name               = "wordpress-key"
  user_data              = file("wordpress-user-data.sh")
  monitoring = true
  ebs_optimized = true
  tags = {
    Name        = "WordPressInstance"
    Environment = "production"
    Project     = "wordpress"
  }
}

# RDS Instance for WordPress Database
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.20"
  instance_class       = "db.t2.micro"
  name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = "wordpresspassword"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  storage_encrypted = true
  backup_retention_period = 12
  iam_database_authentication_enabled = true
  tags = {
    Name        = "WordPressRDS"
    Environment = "production"
    Project     = "wordpress"
  }
}

# DB Subnet Group
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnet.id]
  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = [aws_subnet.public_subnet.id]
  security_groups = [aws_security_group.wordpress_sg.id]

  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 80
    lb_protocol        = "http"
  }

  listener {
    instance_port      = 443
    instance_protocol  = "https"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 10
  }

  instances                   = [aws_instance.wordpress_instance.id]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400
  access_logs {
    bucket        = "wordpress-elb-logs"
    bucket_prefix = "wordpress-elb"
    interval      = 60
  }

  tags = {
    Name        = "WordPressELB"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Auto Scaling Group for EC2 Instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                 = "wordpress-asg"
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  min_size             = 1
  max_size             = 3
  vpc_zone_identifier = aws_subnet.public_subnet.id
  health_check_type    = "EC2"
  health_check_grace_period = 300
  force_delete         = true
  load_balancers = [aws_elb.wordpress_elb.name]
  tag {
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }
  tag {
    key                 = "Environment"
    value               = "production"
    propagate_at_launch = true
  }
  tag {
    key                 = "Project"
    value               = "wordpress"
    propagate_at_launch = true
  }
}

# Launch Configuration for EC2 Instances
resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.wordpress_sg.id]
  key_name               = "wordpress-key"
  user_data              = file("wordpress-user-data.sh")
  ebs_optimized = true
}

# CloudFront Distribution for Content Delivery
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases = ["example.com", "www.example.com"]

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

    viewer_protocol_policy = "https-only"
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
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "sni-only"
  }
  logging_config {
    bucket = "wordpress-cfd-logs.s3.amazonaws.com"
    prefix = "wordpress-cfd"
  }
}

# S3 Bucket for Static Assets
resource "aws_s3_bucket" "wordpress_s3" {
  bucket = "example-bucket"
  acl    = "private"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  logging {
    target_bucket = "wordpress-s3-logs"
    target_prefix = "wordpress-s3/"
  }

  tags = {
    Name        = "WordPressS3"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Route 53 DNS Configuration
resource "aws_route53_record" "wordpress_r53" {
  zone_id = aws_route53_zone.wordpress_r53_zone.id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cfd.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cfd.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "wordpress_r53_zone" {
  name = "example.com"
  tags = {
    Name        = "WordPressR53Zone"
    Environment = "production"
    Project     = "wordpress"
  }
}

# VPC Flow Logs
resource "aws_flow_log" "wordpress_flow_log" {
  iam_role_arn    = aws_iam_role.wordpress_flow_log_role.arn
  log_destination = aws_s3_bucket.wordpress_flow_log_bucket.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.wordpress_vpc.id
}

resource "aws_s3_bucket" "wordpress_flow_log_bucket" {
  bucket = "wordpress-flow-logs"
  acl    = "private"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Name        = "WordPressFlowLogBucket"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_iam_role" "wordpress_flow_log_role" {
  name        = "wordpress-flow-log-role"
  description = "Role for VPC flow logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "WordPressFlowLogRole"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_iam_policy" "wordpress_flow_log_policy" {
  name        = "wordpress-flow-log-policy"
  description = "Policy for VPC flow logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })

  tags = {
    Name        = "WordPressFlowLogPolicy"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_iam_role_policy_attachment" "wordpress_flow_log_attachment" {
  role       = aws_iam_role.wordpress_flow_log_role.name
  policy_arn = aws_iam_policy.wordpress_flow_log_policy.arn
}

output "wordpress_vpc_id" {
  value       = aws_vpc.wordpress_vpc.id
  description = "The ID of the WordPress VPC"
}

output "wordpress_elb_dns_name" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "The DNS name of the WordPress ELB"
}

output "wordpress_rds_endpoint" {
  value       = aws_db_instance.wordpress_rds.endpoint
  description = "The endpoint of the WordPress RDS instance"
}

output "wordpress_s3_bucket_name" {
  value       = aws_s3_bucket.wordpress_s3.id
  description = "The name of the WordPress S3 bucket"
}

output "wordpress_r53_zone_id" {
  value       = aws_route53_zone.wordpress_r53_zone.id
  description = "The ID of the WordPress Route 53 zone"
}
