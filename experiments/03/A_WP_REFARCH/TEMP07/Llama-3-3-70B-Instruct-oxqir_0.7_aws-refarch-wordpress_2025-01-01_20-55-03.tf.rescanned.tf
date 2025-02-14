provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "The availability zones to use"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "The instance type to use"
}

variable "wp_instance_count" {
  type        = number
  default     = 2
  description = "The number of WordPress instances to create"
}

variable "db_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "The instance class to use for the database"
}

variable "db_username" {
  type        = string
  default     = "admin"
  sensitive   = true
  description = "The username to use for the database"
}

variable "db_password" {
  type        = string
  default     = "password123"
  sensitive   = true
  description = "The password to use for the database"
}

variable "domain_name" {
  type        = string
  default     = "example.com"
  description = "The domain name to use"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "prod"
    Project     = "WordPress"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "prod"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "wordpress_public_subnets" {
  count = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = false
  tags = {
    Name        = "WordPressPublicSubnet${count.index + 1}"
    Environment = "prod"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "wordpress_private_subnets" {
  count = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, length(var.availability_zones) + count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "WordPressPrivateSubnet${count.index + 1}"
    Environment = "prod"
    Project     = "WordPress"
  }
}

resource "aws_route_table" "wordpress_public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressPublicRouteTable"
    Environment = "prod"
    Project     = "WordPress"
  }
}

resource "aws_route_table" "wordpress_private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressPrivateRouteTable"
    Environment = "prod"
    Project     = "WordPress"
  }
}

resource "aws_route" "wordpress_public_route" {
  route_table_id         = aws_route_table.wordpress_public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id           = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table_association" "wordpress_public_route_table_association" {
  count = length(var.availability_zones)
  subnet_id      = aws_subnet.wordpress_public_subnets[count.index].id
  route_table_id = aws_route_table.wordpress_public_route_table.id
}

resource "aws_route_table_association" "wordpress_private_route_table_association" {
  count = length(var.availability_zones)
  subnet_id      = aws_subnet.wordpress_private_subnets[count.index].id
  route_table_id = aws_route_table.wordpress_private_route_table.id
}

resource "aws_security_group" "wordpress_sg" {
  name        = "WordPressSG"
  description = "Security group for WordPress instances"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow HTTP traffic"
  }
  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow HTTPS traffic"
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
    Environment = "prod"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "wordpress_db_sg" {
  name        = "WordPressDBSG"
  description = "Security group for WordPress database"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
    description = "Allow MySQL traffic from WordPress instances"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  tags = {
    Name        = "WordPressDBSG"
    Environment = "prod"
    Project     = "WordPress"
  }
}

resource "aws_instance" "wordpress_instances" {
  count = var.wp_instance_count
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  subnet_id = aws_subnet.wordpress_private_subnets[count.index].id
  user_data = file("./wordpress_install.sh")
  monitoring = true
  ebs_optimized = true
  associate_public_ip_address = false
  tags = {
    Name        = "WordPressInstance${count.index + 1}"
    Environment = "prod"
    Project     = "WordPress"
  }
}

resource "aws_db_instance" "wordpress_db" {
  allocated_storage = 20
  engine            = "mysql"
  engine_version    = "5.7"
  instance_class    = var.db_instance_class
  name              = "wordpressdb"
  username          = var.db_username
  password          = var.db_password
  vpc_security_group_ids = [aws_security_group.wordpress_db_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  storage_encrypted = true
  backup_retention_period = 12
  iam_database_authentication_enabled = true
  tags = {
    Name        = "WordPressDB"
    Environment = "prod"
    Project     = "WordPress"
  }
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "WordPressDBSubnetGroup"
  subnet_ids = aws_subnet.wordpress_private_subnets.*.id
  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = "prod"
    Project     = "WordPress"
  }
}

resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = aws_subnet.wordpress_public_subnets.*.id
  security_groups = [aws_security_group.wordpress_sg.id]
  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
  access_logs {
    bucket        = aws_s3_bucket.wordpress_bucket.id
    bucket_prefix = "elb-logs"
    interval      = 60
  }
  tags = {
    Name        = "WordPressELB"
    Environment = "prod"
    Project     = "WordPress"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "WordPressASG"
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  min_size            = 1
  max_size            = 5
  vpc_zone_identifier = aws_subnet.wordpress_private_subnets.*.id
  load_balancers = [aws_elb.wordpress_elb.name]
  tag {
    key                 = "Name"
    value               = "WordPressASG"
    propagate_at_launch = true
  }
  tag {
    key                 = "Environment"
    value               = "prod"
    propagate_at_launch = true
  }
  tag {
    key                 = "Project"
    value               = "WordPress"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  security_groups = [aws_security_group.wordpress_sg.id]
  user_data = file("./wordpress_install.sh")
  ebs_optimized = true
}

resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }
  enabled             = true
  default_root_object = "index.html"
  aliases             = [var.domain_name]
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.wordpress_cert.arn
    ssl_support_method  = "sni-only"
  }
  logging_config {
    bucket = aws_s3_bucket.wordpress_bucket.id
    prefix = "cloudfront-logs"
  }
  tags = {
    Name        = "WordPressCF"
    Environment = "prod"
    Project     = "WordPress"
  }
}

resource "aws_acm_certificate" "wordpress_cert" {
  domain_name       = var.domain_name
  validation_method = "EMAIL"
  tags = {
    Name        = "WordPressCert"
    Environment = "prod"
    Project     = "WordPress"
  }
}

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
      }
    ]
  })
  versioning {
    enabled = true
  }
  logging {
    target_bucket = aws_s3_bucket.wordpress_bucket.id
    target_prefix = "s3-logs"
  }
  tags = {
    Name        = var.domain_name
    Environment = "prod"
    Project     = "WordPress"
  }
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cf.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cf.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
  tags = {
    Name        = var.domain_name
    Environment = "prod"
    Project     = "WordPress"
  }
}

resource "aws_cloudwatch_metric_alarm" "wordpress_cpu_alarm" {
  alarm_name          = "WordPressCPUAlarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods   = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  actions_enabled     = true
  alarm_actions       = [aws_sns_topic.wordpress_sns_topic.arn]
  tags = {
    Name        = "WordPressCPUAlarm"
    Environment = "prod"
    Project     = "WordPress"
  }
}

resource "aws_sns_topic" "wordpress_sns_topic" {
  name = "WordPressSNSTopic"
  kms_master_key_id = aws_kms_key.wordpress_key.id
  tags = {
    Name        = "WordPressSNSTopic"
    Environment = "prod"
    Project     = "WordPress"
  }
}

resource "aws_kms_key" "wordpress_key" {
  description = "Key for WordPress SNS topic"
  tags = {
    Name        = "WordPressKey"
    Environment = "prod"
    Project     = "WordPress"
  }
}

output "wordpress_elb_dns_name" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "The DNS name of the ELB"
}

output "wordpress_cf_distribution_domain_name" {
  value       = aws_cloudfront_distribution.wordpress_cf.domain_name
  description = "The domain name of the CloudFront distribution"
}

output "wordpress_s3_bucket_name" {
  value       = aws_s3_bucket.wordpress_bucket.id
  description = "The name of the S3 bucket"
}

output "wordpress_db_instance_endpoint" {
  value       = aws_db_instance.wordpress_db.endpoint
  description = "The endpoint of the database instance"
  sensitive   = true
}

output "wordpress_db_instance_username" {
  value       = aws_db_instance.wordpress_db.username
  description = "The username of the database instance"
  sensitive   = true
}

output "wordpress_db_instance_password" {
  value       = aws_db_instance.wordpress_db.password
  description = "The password of the database instance"
  sensitive   = true
}
