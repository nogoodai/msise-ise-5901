provider "aws" {
  region = "us-west-2"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "public_subnets" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "CIDR blocks for the public subnets"
}

variable "private_subnets" {
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
  description = "CIDR blocks for the private subnets"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
  description = "Availability zones for the subnets"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for the EC2 instances"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
  description = "ID of the Amazon Linux AMI"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Instance class for the RDS instance"
}

variable "rds_engine" {
  type        = string
  default     = "mysql"
  description = "Engine for the RDS instance"
}

variable "elasticache_node_type" {
  type        = string
  default     = "cache.t2.micro"
  description = "Node type for the ElastiCache cluster"
}

variable "elasticache_engine" {
  type        = string
  default     = "memcached"
  description = "Engine for the ElastiCache cluster"
}

variable "cloudfront_origin" {
  type        = string
  default     = "alb"
  description = "Origin for the CloudFront distribution"
}

variable "cloudfront_behavior" {
  type        = string
  default     = "cache"
  description = "Behavior for the CloudFront distribution"
}

variable "route53_zone_name" {
  type        = string
  default     = "example.com"
  description = "Name of the Route 53 hosted zone"
}

# Create VPC
resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

# Create public subnets
resource "aws_subnet" "public" {
  count             = length(var.public_subnets)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PublicSubnet-${count.index + 1}"
  }
}

# Create private subnets
resource "aws_subnet" "private" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PrivateSubnet-${count.index + 1}"
  }
}

# Create internet gateway
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Create public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = {
    Name = "PublicRouteTable"
  }
}

# Create private route table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public" {
  count          = length(var.public_subnets)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Associate private subnets with private route table
resource "aws_route_table_association" "private" {
  count          = length(var.private_subnets)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Create security group for EC2 instances
resource "aws_security_group" "ec2" {
  vpc_id      = aws_vpc.this.id
  name        = "WordPressEC2SG"
  description = "Security group for EC2 instances"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create security group for RDS instance
resource "aws_security_group" "rds" {
  vpc_id      = aws_vpc.this.id
  name        = "WordPressRDSSG"
  description = "Security group for RDS instance"

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create EC2 instance for WordPress
resource "aws_instance" "this" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.ec2.id]
  subnet_id = aws_subnet.public[0].id
  tags = {
    Name = "WordPressEC2"
  }
}

# Create RDS instance for WordPress database
resource "aws_db_instance" "this" {
  engine         = var.rds_engine
  instance_class = var.rds_instance_class
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name = aws_db_subnet_group.this.name
  tags = {
    Name = "WordPressRDS"
  }
}

resource "aws_db_subnet_group" "this" {
  name       = "wordpress-rds-sg"
  subnet_ids = aws_subnet.private.*.id
  tags = {
    Name = "WordPressRDSSubnetGroup"
  }
}

# Create Elastic Load Balancer
resource "aws_alb" "this" {
  name            = "WordPressALB"
  subnets         = aws_subnet.public.*.id
  security_groups = [aws_security_group.ec2.id]
  tags = {
    Name = "WordPressALB"
  }
}

# Create Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "this" {
  name                = "WordPressASG"
  launch_configuration = aws_launch_configuration.this.name
  min_size            = 1
  max_size            = 3
  vpc_zone_identifier = aws_subnet.public[0].id
  tags = {
    Name = "WordPressASG"
  }
}

resource "aws_launch_configuration" "this" {
  name          = "WordPressLC"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.ec2.id]
  user_data = file("./wordpress.sh")
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "this" {
  origin {
    domain_name = aws_alb.this.dns_name
    origin_id   = "WordPressALB"
  }
  enabled = true
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WordPressALB"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "allow-all"
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
    acm_certificate_arn = aws_acm_certificate.this.arn
  }
}

resource "aws_acm_certificate" "this" {
  domain_name       = var.route53_zone_name
  validation_method = "DNS"
}

resource "aws_route53_record" "this" {
  name    = var.route53_zone_name
  type    = "A"
  zone_id = aws_route53_zone.this.id
  alias {
    name                   = aws_alb.this.dns_name
    zone_id               = aws_alb.this.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "this" {
  name = var.route53_zone_name
}

# Create S3 bucket for static assets
resource "aws_s3_bucket" "this" {
  bucket = "wordpress-static-assets"
  acl    = "private"
  tags = {
    Name = "WordPressStaticAssets"
  }
}

# Create ElastiCache cluster
resource "aws_elasticache_cluster" "this" {
  cluster_id           = "wordpress-elasticache-cluster"
  engine               = var.elasticache_engine
  node_type            = var.elasticache_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.memcached1.4"
  port                 = 11211
  subnet_group_name    = aws_elasticache_subnet_group.this.name
  tags = {
    Name = "WordPressElastiCache"
  }
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "wordpress-elasticache-sg"
  subnet_ids = aws_subnet.private.*.id
  tags = {
    Name = "WordPressElastiCacheSubnetGroup"
  }
}

# Create CloudWatch dashboard
resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "WordPressDashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        x    = 0
        y    = 0
        width = 12
        height = 6
        properties = {
          metrics = [
            [
              "AWS/EC2",
              "CPUUtilization",
              "InstanceId",
              aws_instance.this.id,
            ],
          ]
          period = 300
          stat   = "Average"
          region = "us-west-2"
          title  = "EC2 CPU Utilization"
        }
      },
      {
        type = "metric"
        x    = 12
        y    = 0
        width = 12
        height = 6
        properties = {
          metrics = [
            [
              "AWS/RDS",
              "CPUUtilization",
              "DBInstanceIdentifier",
              aws_db_instance.this.id,
            ],
          ]
          period = 300
          stat   = "Average"
          region = "us-west-2"
          title  = "RDS CPU Utilization"
        }
      },
    ]
  })
}

output "alb_dns_name" {
  value = aws_alb.this.dns_name
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.this.id
}

output "rds_instance_id" {
  value = aws_db_instance.this.id
}

output "ec2_instance_id" {
  value = aws_instance.this.id
}

output "elasticache_cluster_id" {
  value = aws_elasticache_cluster.this.id
}

output "s3_bucket_name" {
  value = aws_s3_bucket.this.id
}

output "route53_zone_id" {
  value = aws_route53_zone.this.id
}
