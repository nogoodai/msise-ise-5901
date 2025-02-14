terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "allowed_ssh_ips" {
  description = "Allowed IPs for SSH access to bastion host"
  type        = list(string)
  default     = ["192.168.1.0/24"] # Replace with specific IPs for security
}

variable "allowed_http_ips" {
  description = "Allowed IPs for HTTP/HTTPS access"
  type        = list(string)
  default     = ["192.168.1.0/24"] # Replace with specific IPs for security
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "public_key_path" {
  description = "Path to the public SSH key"
  type        = string
}

variable "domain_name" {
  description = "Domain name for Route 53"
  type        = string
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "Production"
    Project     = "WordPressDeployment"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "Production"
    Project     = "WordPressDeployment"
  }
}

resource "aws_subnet" "public_subnets" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = element(var.public_subnet_cidrs, count.index)
  map_public_ip_on_launch = false
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "PublicSubnet-${count.index}"
    Environment = "Production"
    Project     = "WordPressDeployment"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "PrivateSubnet-${count.index}"
    Environment = "Production"
    Project     = "WordPressDeployment"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name        = "PublicRouteTable"
    Environment = "Production"
    Project     = "WordPressDeployment"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Security group for web server"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_ips
    description = "Allow HTTP traffic from specific IPs"
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_ips
    description = "Allow HTTPS traffic from specific IPs"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  tags = {
    Name        = "WebServerSG"
    Environment = "Production"
    Project     = "WordPressDeployment"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Security group for database"
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
    description     = "Allow MySQL traffic from web server"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  tags = {
    Name        = "DatabaseSG"
    Environment = "Production"
    Project     = "WordPressDeployment"
  }
}

resource "aws_security_group" "bastion_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Security group for bastion host"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_ips
    description = "Allow SSH access from specific IPs"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  tags = {
    Name        = "BastionSG"
    Environment = "Production"
    Project     = "WordPressDeployment"
  }
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public_subnets[0].id
  security_groups = [aws_security_group.bastion_sg.name]
  key_name      = aws_key_pair.bastion_key.key_name
  associate_public_ip_address = false
  monitoring    = true
  tags = {
    Name        = "BastionHost"
    Environment = "Production"
    Project     = "WordPressDeployment"
  }
}

resource "aws_key_pair" "bastion_key" {
  key_name   = "bastion-key"
  public_key = file(var.public_key_path)
}

resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion.id
  tags = {
    Name        = "BastionEIP"
    Environment = "Production"
    Project     = "WordPressDeployment"
  }
}

resource "aws_efs_file_system" "wordpress_efs" {
  encrypted = true
  kms_key_id = aws_kms_key.efs_key.arn
  tags = {
    Name        = "WordPressEFS"
    Environment = "Production"
    Project     = "WordPressDeployment"
  }
}

resource "aws_efs_mount_target" "wordpress_efs_mount" {
  count          = length(aws_subnet.private_subnets)
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = aws_subnet.private_subnets[count.index].id
  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_kms_key" "efs_key" {
  description = "KMS key for EFS encryption"
  deletion_window_in_days = 10
}

resource "aws_autoscaling_group" "wordpress_asg" {
  launch_configuration = aws_launch_configuration.wordpress_lc.id
  min_size             = 1
  max_size             = 3
  vpc_zone_identifier  = [for subnet in aws_subnet.private_subnets : subnet.id]
  load_balancers       = [aws_elb.wordpress_elb.id]
  tags = [{
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }]
}

resource "aws_launch_configuration" "wordpress_lc" {
  image_id          = data.aws_ami.wordpress_ami.id
  instance_type     = var.instance_type
  security_groups   = [aws_security_group.web_sg.name]
  user_data         = filebase64("wordpress_user_data.sh")
  associate_public_ip_address = false
  iam_instance_profile = aws_iam_instance_profile.wordpress_instance_profile.name
}

resource "aws_iam_instance_profile" "wordpress_instance_profile" {
  name = "WordPressInstanceProfile"
  role = aws_iam_role.wordpress_instance_role.name
}

resource "aws_iam_role" "wordpress_instance_role" {
  name = "WordPressInstanceRole"
  assume_role_policy = data.aws_iam_policy_document.instance_assume_role_policy.json
  tags = {
    Name        = "WordPressInstanceRole"
    Environment = "Production"
    Project     = "WordPressDeployment"
  }
}

data "aws_iam_policy_document" "instance_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "wordpress_instance_policy" {
  role       = aws_iam_role.wordpress_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_elb" "wordpress_elb" {
  name               = "wordpress-elb"
  availability_zones = data.aws_availability_zones.available.names
  listeners {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }
  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  instances = aws_autoscaling_group.wordpress_asg.instances
  security_groups = [aws_security_group.web_sg.id]
  access_logs {
    enabled = true
  }
  tags = {
    Name        = "WordPressELB"
    Environment = "Production"
    Project     = "WordPressDeployment"
  }
}

resource "aws_rds_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  instance_class       = "db.t2.small"
  name                 = "wordpressdb"
  username             = "admin"
  password             = "admin123" # Move to a secure secret manager
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  multi_az             = true
  publicly_accessible  = false
  skip_final_snapshot  = true
  tags = {
    Name        = "WordPressDB"
    Environment = "Production"
    Project     = "WordPressDeployment"
  }
}

resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_cache_behavior {
    target_origin_id       = "wordpress-elb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
  price_class = "PriceClass_100"
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = false
    minimum_protocol_version       = "TLSv1.2_2019"
  }
  logging_config {
    bucket = aws_s3_bucket.log_bucket.id
    include_cookies = false
    prefix = "cloudfront/"
  }
  tags = {
    Name        = "WordPressCDN"
    Environment = "Production"
    Project     = "WordPressDeployment"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-static-assets"
  acl    = "private"
  logging {
    target_bucket = aws_s3_bucket.log_bucket.id
    target_prefix = "s3/"
  }
  versioning {
    enabled = true
  }
  tags = {
    Name        = "WordPressAssets"
    Environment = "Production"
    Project     = "WordPressDeployment"
  }
}

resource "aws_s3_bucket" "log_bucket" {
  bucket = "wordpress-log-bucket"
  acl    = "log-delivery-write"
  tags = {
    Name        = "LogBucket"
    Environment = "Production"
    Project     = "WordPressDeployment"
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
  tags = {
    Name        = var.domain_name
    Environment = "Production"
    Project     = "WordPressDeployment"
  }
}

resource "aws_route53_record" "wordpress_dns" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

data "aws_availability_zones" "available" {}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

data "aws_ami" "wordpress_ami" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["wordpress-ami-*"]
  }
}

output "vpc_id" {
  value       = aws_vpc.wordpress_vpc.id
  description = "The ID of the VPC"
}

output "public_subnet_ids" {
  value       = [for subnet in aws_subnet.public_subnets : subnet.id]
  description = "IDs of the public subnets"
}

output "private_subnet_ids" {
  value       = [for subnet in aws_subnet.private_subnets : subnet.id]
  description = "IDs of the private subnets"
}

output "elb_dns_name" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "DNS name of the ELB"
}

output "rds_endpoint" {
  value       = aws_rds_instance.wordpress_db.endpoint
  description = "Endpoint of the RDS instance"
}

output "cloudfront_domain" {
  value       = aws_cloudfront_distribution.wordpress_cdn.domain_name
  description = "Domain name of the CloudFront distribution"
}
