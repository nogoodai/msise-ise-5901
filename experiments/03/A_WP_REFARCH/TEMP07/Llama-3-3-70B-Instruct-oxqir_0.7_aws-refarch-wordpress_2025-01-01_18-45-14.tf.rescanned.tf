# Configure the AWS provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Define variables for the configuration
variable "region" {
  type        = string
  default     = "us-west-2"
  description = "AWS region"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "VPC CIDR block"
}

variable "subnets" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  description = "Subnet CIDR blocks"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "Availability zones"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "EC2 instance type"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
  description = "EC2 AMI ID"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "RDS instance class"
}

variable "elasticache_node_type" {
  type        = string
  default     = "cache.t2.micro"
  description = "Elasticache node type"
}

variable "cloudfront_ssl_certificate" {
  type        = string
  default     = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  description = "CloudFront SSL certificate ARN"
}

variable "route53_zone_name" {
  type        = string
  default     = "example.com"
  description = "Route 53 zone name"
}

# Create the VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
  }
}

# Create the subnets
resource "aws_subnet" "wordpress_subnets" {
  count             = length(var.subnets)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "WordPressSubnet${count.index + 1}"
    Environment = "production"
  }
}

# Create the internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
  }
}

# Create the route tables
resource "aws_route_table" "wordpress_public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressPublicRT"
    Environment = "production"
  }
}

resource "aws_route_table" "wordpress_private_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressPrivateRT"
    Environment = "production"
  }
}

# Create the route table associations
resource "aws_route_table_association" "wordpress_public_rt_assoc" {
  count          = length(var.subnets)
  subnet_id      = aws_subnet.wordpress_subnets[count.index].id
  route_table_id = aws_route_table.wordpress_public_rt.id
}

# Create the security groups
resource "aws_security_group" "wordpress_web_sg" {
  name        = "WordPressWebSG"
  description = "Security group for WordPress web servers"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow HTTP from VPC"
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow HTTPS from VPC"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all egress traffic"
  }
  tags = {
    Name        = "WordPressWebSG"
    Environment = "production"
  }
}

resource "aws_security_group" "wordpress_db_sg" {
  name        = "WordPressDBSG"
  description = "Security group for WordPress database"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_web_sg.id]
    description     = "Allow MySQL from web servers"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all egress traffic"
  }
  tags = {
    Name        = "WordPressDBSG"
    Environment = "production"
  }
}

# Create the EC2 instances
resource "aws_instance" "wordpress_instances" {
  count         = 2
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.wordpress_web_sg.id
  ]
  subnet_id = aws_subnet.wordpress_subnets[count.index].id
  ebs_optimized = true
  monitoring = true
  tags = {
    Name        = "WordPressInstance${count.index + 1}"
    Environment = "production"
  }
}

# Create the RDS instance
resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = var.rds_instance_class
  name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = random_password.wordpress_db_password.result
  storage_encrypted    = true
  vpc_security_group_ids = [
    aws_security_group.wordpress_db_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_sg.name
  backup_retention_period = 12
  iam_database_authentication_enabled = true
  tags = {
    Name        = "WordPressDB"
    Environment = "production"
  }
}

# Create the Elasticache cluster
resource "aws_elasticache_cluster" "wordpress_elasticache" {
  cluster_id           = "wordpress-elasticache"
  engine               = "redis"
  node_type            = var.elasticache_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis6.x"
  port                 = 6379
  security_group_ids = [
    aws_security_group.wordpress_web_sg.id
  ]
  subnet_group_name = aws_elasticache_subnet_group.wordpress_elasticache.name
  tags = {
    Name        = "WordPressElasticache"
    Environment = "production"
  }
}

# Create the Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.wordpress_subnets.*.id
  security_groups = [aws_security_group.wordpress_web_sg.id]
  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
  access_logs {
    bucket        = aws_s3_bucket.wordpress_s3.id
    bucket_prefix = "elb-logs"
    interval      = 60
  }
  tags = {
    Name        = "WordPressELB"
    Environment = "production"
  }
}

# Create the Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "wordpress-asg"
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  min_size            = 2
  max_size            = 5
  vpc_zone_identifier = aws_subnet.wordpress_subnets.*.id
  load_balancers      = [aws_elb.wordpress_elb.name]
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
  ]
}

# Create the CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }
  enabled             = true
  default_root_object = "index.html"
  aliases             = [var.route53_zone_name]
  viewer_certificate {
    acm_certificate_arn = var.cloudfront_ssl_certificate
    ssl_support_method  = "sni-only"
    minimum_protocol_version = "TLSv1.2_2019"
  }
  logging_config {
    bucket = aws_s3_bucket.wordpress_s3.id
    prefix = "cloudfront-logs/"
  }
  tags = {
    Name        = "WordPressCF"
    Environment = "production"
  }
}

# Create the S3 bucket
resource "aws_s3_bucket" "wordpress_s3" {
  bucket        = "wordpress-s3-bucket"
  acl           = "private"
  force_destroy = true
  versioning {
    enabled = true
  }
  logging {
    target_bucket = aws_s3_bucket.wordpress_s3.id
    target_prefix = "logs/"
  }
  tags = {
    Name        = "WordPressS3"
    Environment = "production"
  }
}

# Create the Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_route53" {
  name = var.route53_zone_name
  tags = {
    Name        = "WordPressRoute53"
    Environment = "production"
  }
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_route53.id
  name    = var.route53_zone_name
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id                = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

# Create the CloudWatch dashboards
resource "aws_cloudwatch_dashboard" "wordpress_dashboard" {
  dashboard_name = "WordPressDashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            {
              label   = "CPUUtilization"
              id      = "cpu"
              region  = var.region
              stat    = "Average"
              period  = 300
              unit    = "Percent"
              values  = [aws_instance.wordpress_instances.*.id]
            },
          ]
        }
      },
    ]
  })
}

output "elb_dns_name" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "The DNS name of the Elastic Load Balancer"
}

output "rds_endpoint" {
  value       = aws_db_instance.wordpress_db.endpoint
  description = "The endpoint of the RDS instance"
}

output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.wordpress_cf.id
  description = "The ID of the CloudFront distribution"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.wordpress_s3.bucket
  description = "The name of the S3 bucket"
}

output "route53_zone_id" {
  value       = aws_route53_zone.wordpress_route53.id
  description = "The ID of the Route 53 zone"
}

resource "aws_db_subnet_group" "wordpress_db_sg" {
  name       = "wordpress_db_sg"
  subnet_ids = aws_subnet.wordpress_subnets.*.id
  tags = {
    Name        = "WordPressDBSG"
    Environment = "production"
  }
}

resource "aws_elasticache_subnet_group" "wordpress_elasticache" {
  name       = "wordpress-elasticache"
  subnet_ids = aws_subnet.wordpress_subnets.*.id
  tags = {
    Name        = "WordPressElasticache"
    Environment = "production"
  }
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.wordpress_web_sg.id
  ]
  ebs_optimized = true
  monitoring = true
  lifecycle {
    create_before_destroy = true
  }
}

resource "random_password" "wordpress_db_password" {
  length = 16
  special = true
}
