# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Define variables
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}

variable "public_subnets" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "The CIDR blocks for the public subnets"
}

variable "private_subnets" {
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
  description = "The CIDR blocks for the private subnets"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
  description = "The availability zones for the subnets"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "The instance type for the EC2 instance"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
  description = "The ID of the AMI for the EC2 instance"
}

variable "db_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "The instance class for the RDS instance"
}

variable "db_username" {
  type        = string
  default     = "admin"
  description = "The username for the RDS instance"
}

variable "db_password" {
  type        = string
  sensitive   = true
  default     = "password123"
  description = "The password for the RDS instance"
}

variable "db_name" {
  type        = string
  default     = "wordpressdb"
  description = "The name of the RDS instance"
}

# Create VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create public subnets
resource "aws_subnet" "public_subnets" {
  count = 2
  cidr_block = var.public_subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicSubnet${count.index + 1}"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create private subnets
resource "aws_subnet" "private_subnets" {
  count = 2
  cidr_block = var.private_subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateSubnet${count.index + 1}"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create public route table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create route for public route table
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public_subnets_association" {
  count = 2
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Create private route table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Associate private subnets with private route table
resource "aws_route_table_association" "private_subnets_association" {
  count = 2
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Create security group for EC2 instances
resource "aws_security_group" "ec2_security_group" {
  name        = "EC2SecurityGroup"
  description = "Allow inbound HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP traffic from anywhere"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS traffic from anywhere"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "EC2SecurityGroup"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create security group for RDS instance
resource "aws_security_group" "rds_security_group" {
  name        = "RDSSecurityGroup"
  description = "Allow inbound MySQL traffic from EC2 instances"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.ec2_security_group.id]
    description = "Allow MySQL traffic from EC2 instances"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "RDSSecurityGroup"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create security group for ELB
resource "aws_security_group" "elb_security_group" {
  name        = "ELBSecurityGroup"
  description = "Allow inbound HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP traffic from anywhere"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS traffic from anywhere"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "ELBSecurityGroup"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create EC2 instance for WordPress
resource "aws_instance" "wordpress_instance" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.ec2_security_group.id]
  subnet_id = aws_subnet.public_subnets[0].id
  key_name = "wordpress_key"
  associate_public_ip_address = false
  monitoring = true
  ebs_optimized = true
  tags = {
    Name        = "WordPressInstance"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create RDS instance for WordPress database
resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = var.db_instance_class
  name                 = var.db_name
  username             = var.db_username
  password             = var.db_password
  vpc_security_group_ids = [aws_security_group.rds_security_group.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  storage_type         = "gp2"
  backup_retention_period = 12
  storage_encrypted = true
  iam_database_authentication_enabled = true
  tags = {
    Name        = "WordPressDB"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create DB subnet group
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress_db_subnet_group"
  subnet_ids = [aws_subnet.private_subnets[0].id, aws_subnet.private_subnets[1].id]
  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = [aws_subnet.public_subnets[0].id, aws_subnet.public_subnets[1].id]
  security_groups = [aws_security_group.elb_security_group.id]

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
  }

  access_logs {
    bucket        = "wordpress-elb-logs"
    bucket_prefix = "elb-logs"
    interval      = 60
  }

  tags = {
    Name        = "WordPressELB"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = [aws_subnet.public_subnets[0].id, aws_subnet.public_subnets[1].id]
  min_size                  = 1
  max_size                  = 3
  desired_capacity          = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  load_balancers = [aws_elb.wordpress_elb.name]
  tags = [
    {
      key                 = "Name"
      value               = "WordPressASG"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = "dev"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = "wordpress"
      propagate_at_launch = true
    }
  ]
}

# Create Launch Configuration for EC2 instances
resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.ec2_security_group.id]
  key_name = "wordpress_key"
  lifecycle {
    create_before_destroy = true
  }
}

# Create CloudFront distribution for content delivery
resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }

  enabled = true
  is_ipv6_enabled = true

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
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
    acm_certificate_arn = aws_acm_certificate.wordpress_cdn.arn
  }

  logging_config {
    bucket = "wordpress-cdn-logs.s3.amazonaws.com"
    prefix = "cdn-logs"
  }

  tags = {
    Name        = "WordPressCDN"
    Environment = "dev"
    Project     = "wordpress"
  }
}

resource "aws_acm_certificate" "wordpress_cdn" {
  domain_name       = "wordpress.example.com"
  validation_method = "DNS"
}

# Create S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-bucket"
  acl    = "private"
  versioning {
    enabled = true
  }

  logging {
    target_bucket = "wordpress-s3-logs"
    target_prefix = "s3-logs"
  }

  tags = {
    Name        = "WordPressBucket"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Create Route 53 DNS configuration
resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "wordpress.example.com"
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

# Create Route 53 zone
resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
  tags = {
    Name        = "WordPressZone"
    Environment = "dev"
    Project     = "wordpress"
  }
}

resource "aws_route53_query_log" "wordpress_log" {
  cloudwatch_log_group_arn = aws_cloudwatch_log_group.wordpress_log.arn
  zone_id                  = aws_route53_zone.wordpress_zone.id
}

resource "aws_cloudwatch_log_group" "wordpress_log" {
  name = "wordpress-log"
}

# Create VPC flow log
resource "aws_flow_log" "wordpress_flow_log" {
  iam_role_arn    = aws_iam_role.wordpress_flow_log.arn
  log_destination = aws_s3_bucket.wordpress_flow_log.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.wordpress_vpc.id
}

resource "aws_s3_bucket" "wordpress_flow_log" {
  bucket = "wordpress-flow-logs"
  acl    = "private"
}

resource "aws_iam_role" "wordpress_flow_log" {
  name        = "wordpress-flow-log"
  description = "Role for VPC flow log"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "vpc-flow-logs.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_policy" "wordpress_flow_log" {
  name        = "wordpress-flow-log"
  description = "Policy for VPC flow log"

  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "logs:CreateLogStream",
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    },
    {
      "Action": "logs:PutLogEvents",
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "wordpress_flow_log" {
  role       = aws_iam_role.wordpress_flow_log.name
  policy_arn = aws_iam_policy.wordpress_flow_log.arn
}

# Output critical information
output "elb_dns_name" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "The DNS name of the ELB"
}

output "rds_endpoint" {
  value       = aws_db_instance.wordpress_db.endpoint
  description = "The endpoint of the RDS instance"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.wordpress_bucket.bucket
  description = "The name of the S3 bucket"
}

output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.wordpress_cdn.id
  description = "The ID of the CloudFront distribution"
}

output "route53_zone_id" {
  value       = aws_route53_zone.wordpress_zone.id
  description = "The ID of the Route 53 zone"
}
