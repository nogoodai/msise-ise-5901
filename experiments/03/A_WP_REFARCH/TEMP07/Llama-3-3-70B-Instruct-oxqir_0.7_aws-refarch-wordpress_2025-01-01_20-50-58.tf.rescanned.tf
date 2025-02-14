provider "aws" {
  region = "us-west-2"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "List of availability zones"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for EC2"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c55b159cbfafe1f0"
  description = "ID of the AMI"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Instance class for RDS"
}

variable "rds_engine" {
  type        = string
  default     = "mysql"
  description = "Engine for RDS"
}

variable "elb_instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for ELB"
}

variable "cloudfront_origin" {
  type        = string
  default     = "S3"
  description = "Origin for CloudFront"
}

variable "cloudfront_ssl_certificate" {
  type        = string
  default     = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  description = "SSL certificate for CloudFront"
}

variable "route53_domain_name" {
  type        = string
  default     = "example.com"
  description = "Domain name for Route 53"
}

# VPC configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Subnets configuration
resource "aws_subnet" "public_subnet" {
  count = 3
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PublicSubnet${count.index + 1}"
    Environment = "dev"
    Project     = "wordpress"
  }
}

resource "aws_subnet" "private_subnet" {
  count = 3
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 3)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PrivateSubnet${count.index + 1}"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Internet Gateway configuration
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Route Tables configuration
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = "dev"
    Project     = "wordpress"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = "dev"
    Project     = "wordpress"
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  count          = 3
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnet_association" {
  count          = 3
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security Groups configuration
resource "aws_security_group" "web_server_sg" {
  name        = "WebServerSG"
  description = "Security group for web server"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
    description = "HTTP from public subnet"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
    description = "HTTPS from public subnet"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
    description = "SSH from public subnet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All traffic to anywhere"
  }

  tags = {
    Name        = "WebServerSG"
    Environment = "dev"
    Project     = "wordpress"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "RDSSG"
  description = "Security group for RDS"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
    description = "MySQL from web server"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All traffic to anywhere"
  }

  tags = {
    Name        = "RDSSG"
    Environment = "dev"
    Project     = "wordpress"
  }
}

resource "aws_security_group" "elb_sg" {
  name        = "ELBSG"
  description = "Security group for ELB"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
    description = "HTTP from public subnet"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
    description = "HTTPS from public subnet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All traffic to anywhere"
  }

  tags = {
    Name        = "ELBSG"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# EC2 instances configuration
resource "aws_instance" "wordpress_instance" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  subnet_id = aws_subnet.private_subnet[0].id
  associate_public_ip_address = false
  tags = {
    Name        = "WordPressInstance"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# RDS instance configuration
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = var.rds_engine
  engine_version       = "8.0.28"
  instance_class       = var.rds_instance_class
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.wordpress_rds_subnet_group.name
  multi_az              = true
  storage_encrypted     = true
  backup_retention_period = 12
  iam_database_authentication_enabled = true
  tags = {
    Name        = "WordPressRDS"
    Environment = "dev"
    Project     = "wordpress"
  }
}

resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = [for subnet in aws_subnet.private_subnet : subnet.id]

  tags = {
    Name        = "WordPressRDSSubnetGroup"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# ELB configuration
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = [for subnet in aws_subnet.public_subnet : subnet.id]
  security_groups = [aws_security_group.elb_sg.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  listener {
    instance_port      = 443
    instance_protocol  = "https"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = var.cloudfront_ssl_certificate
  }

  access_logs {
    bucket        = aws_s3_bucket.wordpress_bucket.id
    bucket_prefix = "logs/"
    enabled       = true
  }

  tags = {
    Name        = "WordPressELB"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Auto Scaling Group configuration
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  max_size                  = 5
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity          = 2
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = [for subnet in aws_subnet.private_subnet : subnet.id]
  load_balancers            = [aws_elb.wordpress_elb.name]

  tag {
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }

  tags = {
    Name        = "WordPressASG"
    Environment = "dev"
    Project     = "wordpress"
  }
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_server_sg.id]
  user_data       = file("./wordpress.sh")
  ebs_optimized = true
  monitoring = true
}

# CloudFront distribution configuration
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.wordpress_bucket.id
    prefix          = "logs/"
  }

  aliases = ["${var.route53_domain_name}"]

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
    acm_certificate_arn = var.cloudfront_ssl_certificate
    ssl_support_method  = "sni-only"
    minimum_protocol_version = "TLSv1.2_2018"
  }

  tags = {
    Name        = "WordPressCloudFront"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# S3 bucket configuration
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = var.route53_domain_name
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
    target_bucket = aws_s3_bucket.wordpress_bucket.id
    target_prefix = "logs/"
  }

  tags = {
    Name        = "WordPressBucket"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Route 53 configuration
resource "aws_route53_zone" "wordpress_route53" {
  name = var.route53_domain_name
  tags = {
    Name        = "WordPressRoute53"
    Environment = "dev"
    Project     = "wordpress"
  }
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53.zone_id
  name    = var.route53_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cfd.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cfd.zone_id
    evaluate_target_health = false
  }
}

# VPC Flow Logs configuration
resource "aws_flow_log" "wordpress_vpc_flow_log" {
  iam_role_arn    = aws_iam_role.wordpress_vpc_flow_log_role.arn
  log_destination = aws_s3_bucket.wordpress_bucket.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.wordpress_vpc.id
}

resource "aws_iam_role" "wordpress_vpc_flow_log_role" {
  name        = "WordPressVPCFlowLogRole"
  description = "Role for VPC Flow Logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Effect = "Allow"
        Sid      = ""
      }
    ]
  })
}

resource "aws_iam_policy" "wordpress_vpc_flow_log_policy" {
  name        = "WordPressVPCFlowLogPolicy"
  description = "Policy for VPC Flow Logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "wordpress_vpc_flow_log_policy_attachment" {
  role       = aws_iam_role.wordpress_vpc_flow_log_role.name
  policy_arn = aws_iam_policy.wordpress_vpc_flow_log_policy.arn
}

output "vpc_id" {
  value       = aws_vpc.wordpress_vpc.id
  description = "ID of the VPC"
}

output "rds_instance_address" {
  value       = aws_db_instance.wordpress_rds.address
  description = "Address of the RDS instance"
}

output "elb_dns_name" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "DNS name of the ELB"
}

output "cloudfront_distribution_domain_name" {
  value       = aws_cloudfront_distribution.wordpress_cfd.domain_name
  description = "Domain name of the CloudFront distribution"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.wordpress_bucket.id
  description = "Name of the S3 bucket"
}

output "route53_zone_id" {
  value       = aws_route53_zone.wordpress_route53.zone_id
  description = "ID of the Route 53 zone"
}
