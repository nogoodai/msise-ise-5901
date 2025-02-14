# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Define variables
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "subnet_cidr" {
  type        = string
  default     = "10.0.1.0/24"
  description = "CIDR block for the subnet"
}

variable "availability_zone" {
  type        = string
  default     = "us-west-2a"
  description = "Availability zone for the subnet"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Type of the EC2 instance"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
  description = "ID of the AMI for the EC2 instance"
}

variable "db_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Class of the RDS instance"
}

variable "db_username" {
  type        = string
  default     = "admin"
  sensitive   = true
  description = "Username for the RDS instance"
}

variable "db_password" {
  type        = string
  default     = "password123"
  sensitive   = true
  description = "Password for the RDS instance"
}

variable "environment" {
  type        = string
  default     = "production"
  description = "Environment for the resources"
}

variable "project" {
  type        = string
  default     = "wordpress"
  description = "Project name for the resources"
}

# Create VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = var.environment
    Project     = var.project
  }
}

# Create subnets
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.subnet_cidr
  availability_zone = var.availability_zone
  tags = {
    Name        = "PublicSubnet"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = var.availability_zone
  tags = {
    Name        = "PrivateSubnet"
    Environment = var.environment
    Project     = var.project
  }
}

# Create internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = var.environment
    Project     = var.project
  }
}

# Create route tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = var.environment
    Project     = var.project
  }
}

# Create route table associations
resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnet_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

# Create security groups
resource "aws_security_group" "web_server_sg" {
  name        = "WebServerSG"
  description = "Allow inbound HTTP and HTTPS traffic"
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
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "WebServerSG"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group" "db_sg" {
  name        = "DBSG"
  description = "Allow inbound MySQL traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    description = "Allow MySQL traffic from web server"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "DBSG"
    Environment = var.environment
    Project     = var.project
  }
}

# Create EC2 instances
resource "aws_instance" "wordpress_instance" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  subnet_id = aws_subnet.public_subnet.id
  associate_public_ip_address = false
  ebs_optimized = true
  monitoring = true
  tags = {
    Name        = "WordPressInstance"
    Environment = var.environment
    Project     = var.project
  }
}

# Create RDS instance
resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.20"
  instance_class       = var.db_instance_class
  name                 = "wordpressdb"
  username             = var.db_username
  password             = var.db_password
  parameter_group_name = "default.mysql8.0"
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  storage_encrypted = true
  iam_database_authentication_enabled = true
  backup_retention_period = 12
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]
  tags = {
    Name        = "WordPressDB"
    Environment = var.environment
    Project     = var.project
  }
}

# Create DB subnet group
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress_db_subnet_group"
  subnet_ids = [aws_subnet.private_subnet.id]
  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = var.environment
    Project     = var.project
  }
}

# Create Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = [aws_subnet.public_subnet.id]
  security_groups = [aws_security_group.web_server_sg.id]
  listener {
    lb_port       = 80
    lb_protocol   = "http"
    instance_port = 80
    instance_protocol = "http"
  }
  access_logs {
    bucket        = "elb-access-logs"
    bucket_prefix = "elb-access-logs"
    interval      = 60
  }
  tags = {
    Name        = "WordPressELB"
    Environment = var.environment
    Project     = var.project
  }
}

# Create Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "ELB"
  launch_configuration      = aws_launch_configuration.wordpress_launch_config.name
  vpc_zone_identifier       = aws_subnet.public_subnet.id
  load_balancers = [aws_elb.wordpress_elb.name]
  tags = {
    Name        = "WordPressASG"
    Environment = var.environment
    Project     = var.project
  }
}

# Create Launch Configuration
resource "aws_launch_configuration" "wordpress_launch_config" {
  name          = "WordPressLaunchConfig"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_server_sg.id]
  user_data = file("${path.module}/wordpress-install.sh")
  lifecycle {
    create_before_destroy = true
  }
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_instance.wordpress_instance.private_ip
    origin_id   = "WordPressOrigin"
  }
  enabled = true
  default_root_object = "index.html"
  aliases = ["example.com"]
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WordPressOrigin"
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
  logging_config {
    bucket = "cloudfront-logs.s3.amazonaws.com"
    prefix = "cloudfront-logs/"
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "sni-only"
    minimum_protocol_version = "TLSv1.2_2019"
  }
  tags = {
    Name        = "WordPressDistribution"
    Environment = var.environment
    Project     = var.project
  }
}

# Create S3 bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "example-bucket"
  acl    = "private"
  versioning {
    enabled = true
  }
  logging {
    target_bucket = "s3-access-logs"
    target_prefix = "s3-access-logs/"
  }
  tags = {
    Name        = "WordPressBucket"
    Environment = var.environment
    Project     = var.project
  }
}

# Create Route 53 DNS configuration
resource "aws_route53_record" "wordpress_record" {
  zone_id = "Z123456789012"
  name    = "example.com"
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id                = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

# Create VPC flow log
resource "aws_flow_log" "wordpress_flow_log" {
  iam_role_arn    = aws_iam_role.flow_log_role.arn
  log_destination = aws_s3_bucket.flow_log_bucket.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.wordpress_vpc.id
}

# Create IAM role for VPC flow log
resource "aws_iam_role" "flow_log_role" {
  name        = "FlowLogRole"
  description = "IAM role for VPC flow log"

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

# Create S3 bucket for VPC flow log
resource "aws_s3_bucket" "flow_log_bucket" {
  bucket = "flow-logs"
  acl    = "private"
}

# Create IAM policy for VPC flow log
resource "aws_iam_policy" "flow_log_policy" {
  name        = "FlowLogPolicy"
  description = "IAM policy for VPC flow log"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "logs:CreateLogGroup"
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      },
      {
        Action = "logs:CreateLogStream"
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      },
      {
        Action = "logs:PutLogEvents"
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      }
    ]
  })
}

# Attach IAM policy to IAM role
resource "aws_iam_role_policy_attachment" "flow_log_attachment" {
  role       = aws_iam_role.flow_log_role.name
  policy_arn = aws_iam_policy.flow_log_policy.arn
}

output "elb_dns_name" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "DNS name of the Elastic Load Balancer"
}

output "instance_id" {
  value       = aws_instance.wordpress_instance.id
  description = "ID of the EC2 instance"
}

output "db_instance_id" {
  value       = aws_db_instance.wordpress_db.id
  description = "ID of the RDS instance"
}
