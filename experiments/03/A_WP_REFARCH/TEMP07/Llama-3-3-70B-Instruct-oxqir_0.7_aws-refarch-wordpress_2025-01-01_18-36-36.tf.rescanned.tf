provider "aws" {
  region = "us-west-2"
  required_providers {
    aws = "= 5.1.0"
  }
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "A list of availability zones"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "The type of instance to start"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
  description = "The ID of the AMI to use"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "The instance class for the RDS instance"
}

variable "database_username" {
  type        = string
  default     = "wordpress"
  description = "The username for the database"
}

variable "database_password" {
  type        = string
  default     = "password123"
  sensitive   = true
  description = "The password for the database"
}

variable "database_name" {
  type        = string
  default     = "wordpressdb"
  description = "The name of the database"
}

variable "domain_name" {
  type        = string
  default     = "example.com"
  description = "The domain name for the website"
}

variable "cloudfront_ssl_certificate" {
  type        = string
  default     = "arn:aws:iam::123456789012:server-certificate/example"
  description = "The ARN of the SSL certificate for CloudFront"
}

# Networking
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPress-VPC"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPress-IGW"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table" "wordpress_public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name        = "WordPress-Public-RT"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table" "wordpress_private_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPress-Private-RT"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "wordpress_public_subnet" {
  count = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "WordPress-Public-Subnet-${count.index + 1}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "wordpress_private_subnet" {
  count = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + length(var.availability_zones))
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "WordPress-Private-Subnet-${count.index + 1}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table_association" "wordpress_public_rt_assoc" {
  count = length(var.availability_zones)
  subnet_id      = aws_subnet.wordpress_public_subnet[count.index].id
  route_table_id = aws_route_table.wordpress_public_rt.id
}

resource "aws_route_table_association" "wordpress_private_rt_assoc" {
  count = length(var.availability_zones)
  subnet_id      = aws_subnet.wordpress_private_subnet[count.index].id
  route_table_id = aws_route_table.wordpress_private_rt.id
}

# Security Groups
resource "aws_security_group" "wordpress_ec2_sg" {
  name        = "WordPress-EC2-SG"
  description = "Security Group for WordPress EC2 instances"
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
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH traffic from anywhere"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outgoing traffic"
  }
  tags = {
    Name        = "WordPress-EC2-SG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "wordpress_rds_sg" {
  name        = "WordPress-RDS-SG"
  description = "Security Group for WordPress RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_ec2_sg.id]
    description     = "Allow MySQL traffic from EC2 instances"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outgoing traffic"
  }
  tags = {
    Name        = "WordPress-RDS-SG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# EC2 Instances
resource "aws_instance" "wordpress_ec2_instance" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.wordpress_ec2_sg.id
  ]
  subnet_id = aws_subnet.wordpress_private_subnet[0].id
  associate_public_ip_address = false
  monitoring = true
  ebs_optimized = true
  tags = {
    Name        = "WordPress-EC2-Instance"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# RDS Instance
resource "aws_db_instance" "wordpress_rds_instance" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = var.rds_instance_class
  name                 = var.database_name
  username             = var.database_username
  password             = var.database_password
  vpc_security_group_ids = [
    aws_security_group.wordpress_rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  storage_encrypted = true
  backup_retention_period = 12
  iam_database_authentication_enabled = true
  monitoring_interval = "30"
  tags = {
    Name        = "WordPress-RDS-Instance"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = aws_subnet.wordpress_private_subnet[*].id
  tags = {
    Name        = "WordPress-RDS-Subnet-Group"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.wordpress_public_subnet[*].id
  security_groups = [aws_security_group.wordpress_ec2_sg.id]
  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
  access_logs {
    bucket        = "wordpress-elb-logs"
    bucket_prefix = "wordpress-elb"
    interval      = 60
  }
  tags = {
    Name        = "WordPress-ELB"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  max_size                  = 3
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = aws_subnet.wordpress_private_subnet[*].id
  load_balancers = [
    aws_elb.wordpress_elb.name
  ]
  tag {
    key                 = "Name"
    value               = "WordPress-EC2-Instance"
    propagate_at_launch = true
  }
  tags = [
    {
      key                 = "Environment"
      value               = "Production"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = "WordPress"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.wordpress_ec2_sg.id
  ]
  user_data = file("${path.module}/wordpress_userdata.sh")
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPress-ELB"
  }
  enabled = true
  default_root_object = "index.html"
  aliases = [var.domain_name]
  custom_error_response {
    error_code = 404
    response_code = 200
    response_page_path = "/404.html"
  }
  viewer_certificate {
    acm_certificate_arn = var.cloudfront_ssl_certificate
    ssl_support_method = "sni-only"
    minimum_protocol_version = "TLSv1.2_2019"
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  logging_config {
    bucket = "wordpress-cfd-logs.s3.amazonaws.com"
    prefix = "wordpress-cfd"
  }
  tags = {
    Name        = "WordPress-CFD"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# S3 Bucket
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = var.domain_name
  acl    = "private"
  versioning {
    enabled = true
  }
  logging {
    target_bucket = "wordpress-s3-logs"
    target_prefix = "wordpress-s3"
  }
  tags = {
    Name        = "WordPress-S3-Bucket"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress_r53_zone" {
  name = var.domain_name
  tags = {
    Name        = "WordPress-R53-Zone"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route53_record" "wordpress_r53_record" {
  zone_id = aws_route53_zone.wordpress_r53_zone.zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

output "wordpress_elb_dns_name" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "The DNS name of the ELB"
}

output "wordpress_cfd_domain_name" {
  value       = aws_cloudfront_distribution.wordpress_cfd.domain_name
  description = "The domain name of the CloudFront distribution"
}

output "wordpress_r53_zone_id" {
  value       = aws_route53_zone.wordpress_r53_zone.zone_id
  description = "The ID of the Route 53 zone"
}
