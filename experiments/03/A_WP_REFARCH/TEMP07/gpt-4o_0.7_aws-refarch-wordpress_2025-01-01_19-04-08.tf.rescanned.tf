terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy to."
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets."
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  description = "Availability zones for deployment."
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
}

variable "allowed_ssh_ips" {
  description = "Allowed IPs for SSH access."
  type        = list(string)
  default     = ["192.168.1.0/24"]  # Example restricted IP
}

variable "project_name" {
  description = "The name of the project for tagging."
  type        = string
  default     = "wordpress-project"
}

variable "ssl_certificate_id" {
  description = "The SSL certificate ID for the ELB."
  type        = string
}

variable "key_name" {
  description = "The name of the SSH key pair to use for instances."
  type        = string
}

variable "domain_name" {
  description = "The domain name for the Route 53 record."
  type        = string
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "${var.project_name}-igw"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false
  tags = {
    Name        = "${var.project_name}-public-${count.index}"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "${var.project_name}-private-${count.index}"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Security group for web access"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP traffic"
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS traffic"
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_ips
    description = "Allow SSH traffic from specific IPs"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  tags = {
    Name        = "${var.project_name}-web-sg"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Security group for database access"
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
    description     = "Allow MySQL traffic from web servers"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  tags = {
    Name        = "${var.project_name}-db-sg"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_instance" "wordpress" {
  ami                         = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 AMI
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public[0].id
  security_groups            = [aws_security_group.web_sg.name]
  associate_public_ip_address = false
  ebs_optimized               = true
  monitoring                  = true
  key_name                    = var.key_name
  tags = {
    Name        = "${var.project_name}-wordpress"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_elb" "wordpress_elb" {
  name               = "${var.project_name}-elb"
  availability_zones = var.availability_zones
  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }
  listener {
    instance_port     = 443
    instance_protocol = "HTTP"
    lb_port           = 443
    lb_protocol       = "HTTPS"
    ssl_certificate_id = var.ssl_certificate_id
  }
  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  instances = [aws_instance.wordpress.id]
  access_logs {
    enabled = true
    bucket  = aws_s3_bucket.wordpress_assets.id
    prefix  = "elb-logs"
  }
  tags = {
    Name        = "${var.project_name}-elb"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_autoscaling_group" "asg" {
  availability_zones   = var.availability_zones
  max_size             = 3
  min_size             = 1
  desired_capacity     = 1
  launch_configuration = aws_launch_configuration.wordpress_launch_config.id
  vpc_zone_identifier  = aws_subnet.public[*].id
  tags = [
    {
      key                 = "Name"
      value               = "${var.project_name}-asg"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_launch_config" {
  image_id        = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 AMI
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.web_sg.id]
  user_data       = file("wordpress-user-data.sh")
  key_name        = var.key_name
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "wordpress_db" {
  identifier                        = "${var.project_name}-db"
  allocated_storage                 = 20
  storage_type                      = "gp2"
  engine                            = "mysql"
  engine_version                    = "8.0"
  instance_class                    = "db.t2.small"
  name                              = "wordpressdb"
  username                          = "admin"
  password                          = var.db_password
  skip_final_snapshot               = true
  multi_az                          = true
  storage_encrypted                 = true
  iam_database_authentication_enabled = true
  backup_retention_period           = 7
  enabled_cloudwatch_logs_exports   = ["error", "general", "slowquery"]
  vpc_security_group_ids            = [aws_security_group.db_sg.id]
  tags = {
    Name        = "${var.project_name}-db"
    Environment = "production"
    Project     = var.project_name
  }
}

variable "db_password" {
  description = "The password for the RDS instance."
  type        = string
  sensitive   = true
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "${var.project_name}-assets"
  acl    = "private"
  logging {
    target_bucket = aws_s3_bucket.wordpress_assets.id
    target_prefix = "s3-logs/"
  }
  versioning {
    enabled = true
  }
  tags = {
    Name        = "${var.project_name}-assets"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.wordpress_assets.id}"
  }
  enabled             = true
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.wordpress_assets.id}"
    viewer_protocol_policy = "redirect-to-https"
  }
  viewer_certificate {
    acm_certificate_arn = var.ssl_certificate_id
    minimum_protocol_version = "TLSv1.2_2019"
    ssl_support_method = "sni-only"
  }
  logging_config {
    bucket = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    include_cookies = false
    prefix = "cloudfront-logs/"
  }
  tags = {
    Name        = "${var.project_name}-cdn"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
  tags = {
    Name        = "${var.project_name}-zone"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id                = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = true
  }
}

output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
  description = "The ID of the VPC."
}

output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
  description = "The DNS name of the ELB."
}

output "db_instance_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
  description = "The endpoint of the RDS instance."
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_assets.id
  description = "The name of the S3 bucket."
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cdn.domain_name
  description = "The domain name of the CloudFront distribution."
}

output "route53_zone_id" {
  value = aws_route53_zone.wordpress_zone.zone_id
  description = "The ID of the Route 53 hosted zone."
}
