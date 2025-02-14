# Terraform configuration for AWS resources

# Specify the provider and version
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.1.0"
    }
  }
}

# Configure the AWS provider
provider "aws" {
  region = "us-west-2"
}

# Variables for user-configurable values
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "The availability zones for the subnets"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "The instance type for the EC2 instances"
}

variable "db_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "The instance class for the RDS instance"
}

variable "domain_name" {
  type        = string
  default     = "example.com"
  description = "The domain name for the Route 53 configuration"
}

# Networking resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "public_subnets" {
  count             = 3
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PublicSubnet${count.index + 1}"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = 3
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 3)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PrivateSubnet${count.index + 1}"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table_association" "public_subnet_associations" {
  count          = 3
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Security groups
resource "aws_security_group" "wordpress_sg" {
  name        = "WordPressSG"
  description = "Security group for WordPress instances"
  vpc_id      = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressSG"
    Environment = "production"
    Project     = "WordPress"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
    description = "Allow HTTP traffic from specific IP range"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
    description = "Allow HTTPS traffic from specific IP range"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
    description = "Allow SSH traffic from specific IP range"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outgoing traffic"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "RDSSG"
  description = "Security group for RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "RDSSG"
    Environment = "production"
    Project     = "WordPress"
  }

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
    description = "Allow all outgoing traffic"
  }
}

# EC2 instances
resource "aws_instance" "wordpress_instance" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.wordpress_sg.id
  ]
  subnet_id = aws_subnet.public_subnets[0].id
  associate_public_ip_address = false
  monitoring = true
  ebs_optimized = true
  tags = {
    Name        = "WordPressInstance"
    Environment = "production"
    Project     = "WordPress"
  }
}

# RDS instance
resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = var.db_instance_class
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  vpc_security_group_ids = [
    aws_security_group.rds_sg.id
  ]
  backup_retention_period = 12
  storage_encrypted = true
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]
  tags = {
    Name        = "WordPressDB"
    Environment = "production"
    Project     = "WordPress"
  }
}

# DB subnet group
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "WordPressDBSubnetGroup"
  subnet_ids = aws_subnet.private_subnets[*].id
  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = "production"
    Project     = "WordPress"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = aws_subnet.public_subnets[*].id
  security_groups = [aws_security_group.wordpress_sg.id]
  access_logs {
    bucket        = aws_s3_bucket.wordpress_bucket.bucket
    bucket_prefix  = "elb-access-logs"
    interval      = 60
  }
  tags = {
    Name        = "WordPressELB"
    Environment = "production"
    Project     = "WordPress"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "WordPressASG"
  max_size            = 5
  min_size            = 1
  desired_capacity    = 1
  launch_configuration = aws_launch_configuration.wordpress_launch_config.name
  vpc_zone_identifier = aws_subnet.public_subnets[0].id
  load_balancers = [aws_elb.wordpress_elb.name]
  tags = [
    {
      key                 = "Name"
      value               = "WordPressASG"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = "production"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = "WordPress"
      propagate_at_launch = true
    }
  ]
}

# Launch configuration
resource "aws_launch_configuration" "wordpress_launch_config" {
  name          = "WordPressLaunchConfig"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.wordpress_sg.id
  ]
  user_data = file("${path.module}/wordpress_user_data.sh")
  ebs_optimized = true
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [var.domain_name]
  viewer_certificate {
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "sni-only"
    minimum_protocol_version = "TLSv1.2_2018"
  }
  logging_config {
    bucket = aws_s3_bucket.wordpress_bucket.bucket
    prefix = "cloudfront-access-logs"
  }
  tags = {
    Name        = "WordPressCloudFrontDistribution"
    Environment = "production"
    Project     = "WordPress"
  }
}

# S3 bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = var.domain_name
  acl    = "private"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource = "arn:aws:s3:::${var.domain_name}/*"
      },
    ]
  })
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
    target_prefix = "s3-access-logs"
  }
  tags = {
    Name        = var.domain_name
    Environment = "production"
    Project     = "WordPress"
  }
}

# Route 53 configuration
resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
  tags = {
    Name        = var.domain_name
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

# Flow logs
resource "aws_flow_log" "wordpress_vpc_flow_log" {
  iam_role_arn    = aws_iam_role.wordpress_vpc_flow_log_role.arn
  log_destination = aws_s3_bucket.wordpress_bucket.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.wordpress_vpc.id
}

resource "aws_iam_role" "wordpress_vpc_flow_log_role" {
  name        = "WordPressVPCFlowLogRole"
  description = "Role for VPC flow logs"

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
      },
    ]
  })
}

resource "aws_iam_policy" "wordpress_vpc_flow_log_policy" {
  name        = "WordPressVPCFlowLogPolicy"
  description = "Policy for VPC flow logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "wordpress_vpc_flow_log_attachment" {
  role       = aws_iam_role.wordpress_vpc_flow_log_role.name
  policy_arn = aws_iam_policy.wordpress_vpc_flow_log_policy.arn
}

# Outputs
output "wordpress_elb_dns_name" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "The DNS name of the Elastic Load Balancer"
}

output "wordpress_rds_endpoint" {
  value       = aws_db_instance.wordpress_db.endpoint
  description = "The endpoint of the RDS instance"
}

output "wordpress_s3_bucket_name" {
  value       = aws_s3_bucket.wordpress_bucket.bucket
  description = "The name of the S3 bucket"
}

output "wordpress_cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.wordpress_distribution.id
  description = "The ID of the CloudFront distribution"
}

output "wordpress_route53_zone_id" {
  value       = aws_route53_zone.wordpress_zone.id
  description = "The ID of the Route 53 zone"
}
