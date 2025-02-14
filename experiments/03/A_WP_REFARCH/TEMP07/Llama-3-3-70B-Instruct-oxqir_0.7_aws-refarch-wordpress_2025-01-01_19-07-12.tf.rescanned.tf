# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
}

# Variable definitions for user-configurable values
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "Availability zones for the subnets"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for the EC2 instances"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c55b159cbfafe1f0"
  description = "ID of the Amazon Linux AMI"
}

variable "db_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Instance class for the RDS instance"
}

variable "db_username" {
  type        = string
  default     = "wordpress"
  description = "Username for the RDS instance"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "Password for the RDS instance"
}

variable "project_name" {
  type        = string
  default     = "wordpress"
  description = "Name of the project"
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Environment of the project"
}

# Create a VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Create subnets
resource "aws_subnet" "public_subnets" {
  count = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "${var.project_name}-public-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "private_subnets" {
  count = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, length(var.availability_zones) + count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "${var.project_name}-private-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Create an internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Create route tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "${var.project_name}-public-route-table"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "${var.project_name}-private-route-table"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Associate subnets with route tables
resource "aws_route_table_association" "public_subnets_association" {
  count = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnets_association" {
  count = length(var.availability_zones)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Create security groups
resource "aws_security_group" "ec2_sg" {
  name        = "${var.project_name}-ec2-sg"
  description = "Security group for EC2 instances"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow HTTP traffic from within the VPC"
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow HTTPS traffic from within the VPC"
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow SSH traffic from within the VPC"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outgoing traffic"
  }
  tags = {
    Name        = "${var.project_name}-ec2-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
    description = "Allow MySQL traffic from EC2 instances"
  }
  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_security_group" "elb_sg" {
  name        = "${var.project_name}-elb-sg"
  description = "Security group for ELB"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow HTTP traffic from within the VPC"
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow HTTPS traffic from within the VPC"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outgoing traffic"
  }
  tags = {
    Name        = "${var.project_name}-elb-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Create EC2 instances
resource "aws_instance" "wordpress_ec2" {
  count = length(var.availability_zones)
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id = aws_subnet.public_subnets[count.index].id
  tags = {
    Name        = "${var.project_name}-ec2-${count.index + 1}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Create RDS instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version      = "5.7"
  instance_class      = var.db_instance_class
  name                 = "wordpressdb"
  username             = var.db_username
  password             = var.db_password
  db_subnet_group_name = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  storage_encrypted  = true
  backup_retention_period = 12
  multi_az = true
  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "${var.project_name}-rds-subnet-group"
  subnet_ids = aws_subnet.private_subnets.*.id
  tags = {
    Name        = "${var.project_name}-rds-subnet-group"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Create ELB
resource "aws_elb" "wordpress_elb" {
  name            = "${var.project_name}-elb"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.elb_sg.id]
  access_logs {
    bucket        = aws_s3_bucket.wordpress_s3.id
    bucket_prefix = "${var.project_name}-elb-logs"
    interval      = 60
  }
  tags = {
    Name        = "${var.project_name}-elb"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_elb_listener" "wordpress_elb_listener" {
  load_balancer_name = aws_elb.wordpress_elb.name
  port              = "80"
  protocol          = "HTTP"
  default_action {
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
    type             = "forward"
  }
}

resource "aws_lb_target_group" "wordpress_tg" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "${var.project_name}-tg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lb_target_group_attachment" "wordpress_tg_attachment" {
  count            = length(var.availability_zones)
  target_group_arn = aws_lb_target_group.wordpress_tg.arn
  target_id        = aws_instance.wordpress_ec2[count.index].id
  port             = 80
}

# Create Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "${var.project_name}-asg"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 1
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id
  load_balancers            = [aws_elb.wordpress_elb.name]
  tags = {
    Name        = "${var.project_name}-asg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "${var.project_name}-lc"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.ec2_sg.id]
  lifecycle {
    create_before_destroy = true
  }
  ebs_optimized = true
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "${var.project_name}-elb"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = ["example.com"]
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.cert.arn
  }
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${var.project_name}-elb"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.wordpress_s3.id
    prefix          = "${var.project_name}-cfd-logs"
  }
  tags = {
    Name        = "${var.project_name}-cfd"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_acm_certificate" "cert" {
  domain_name       = "example.com"
  validation_method = "DNS"
}

# Create S3 bucket
resource "aws_s3_bucket" "wordpress_s3" {
  bucket = "${var.project_name}-s3-bucket"
  acl    = "private"
  versioning {
    enabled = true
  }
  logging {
    target_bucket = aws_s3_bucket.wordpress_s3.id
    target_prefix = "${var.project_name}-s3-logs/"
  }
  tags = {
    Name        = "${var.project_name}-s3-bucket"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Create Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_r53" {
  name = "example.com"
  tags = {
    Name        = "${var.project_name}-r53"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route53_record" "wordpress_r53_record" {
  zone_id = aws_route53_zone.wordpress_r53.zone_id
  name    = "example.com"
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

# Create CloudWatch logs and alarms
resource "aws_cloudwatch_log_group" "wordpress_cwlg" {
  name = "${var.project_name}-cwlg"
  retention_in_days = 7
  tags = {
    Name        = "${var.project_name}-cwlg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "wordpress_cwma" {
  alarm_name                = "${var.project_name}-cwma"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = "2"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "300"
  statistic                 = "Average"
  threshold                 = "80"
  alarm_description         = "This metric alarm monitors ec2 cpu utilization"
  actions_enabled          = "true"
  alarm_actions           = [aws_sns_topic.wordpress_sns.arn]
  insufficient_data_actions = []
  ok_actions                = []
  tags = {
    Name        = "${var.project_name}-cwma"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_sns_topic" "wordpress_sns" {
  name = "${var.project_name}-sns"
  kms_master_key_id = aws_kms_key.wordpress_kms_key.arn
  tags = {
    Name        = "${var.project_name}-sns"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_kms_key" "wordpress_kms_key" {
  description             = "KMS key for SNS topic"
  deletion_window_in_days = 10
  tags = {
    Name        = "${var.project_name}-kms-key"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Output critical information
output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
  description = "The DNS name of the ELB"
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
  description = "The endpoint of the RDS instance"
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3.bucket
  description = "The name of the S3 bucket"
}

output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cfd.domain_name
  description = "The domain name of the CloudFront distribution"
}

output "route53_record_name" {
  value = aws_route53_record.wordpress_r53_record.name
  description = "The name of the Route 53 record"
}
