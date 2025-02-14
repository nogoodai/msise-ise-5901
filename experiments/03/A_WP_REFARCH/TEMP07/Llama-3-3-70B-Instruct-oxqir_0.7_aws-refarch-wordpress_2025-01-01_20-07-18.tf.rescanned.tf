# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# VPC Configuration
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Subnets
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

resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnets)
  cidr_block        = var.public_subnets[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  availability_zone = "us-west-2${count.index % 2 + 1}"
  tags = {
    Name        = "PublicSubnet${count.index + 1}"
    Environment = "dev"
    Project     = "wordpress"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnets)
  cidr_block        = var.private_subnets[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  availability_zone = "us-west-2${count.index % 2 + 1}"
  tags = {
    Name        = "PrivateSubnet${count.index + 1}"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Route Tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = "dev"
    Project     = "wordpress"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table_association" "public_subnets" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Security Groups
resource "aws_security_group" "web_server_sg" {
  name        = "WordPressWebServerSG"
  description = "Allow HTTP and HTTPS traffic from anywhere"
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
    Name        = "WordPressWebServerSG"
    Environment = "dev"
    Project     = "wordpress"
  }
}

resource "aws_security_group" "db_sg" {
  name        = "WordPressDBSG"
  description = "Allow MySQL traffic from web server"
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
    Name        = "WordPressDBSG"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# EC2 Instances
variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "The instance type for the EC2 instances"
}

resource "aws_instance" "wordpress_ec2" {
  ami           = "ami-0c2ab3b8efb09f272"
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  subnet_id = aws_subnet.public_subnets[0].id
  key_name               = "wordpress-key"
  user_data              = file("./wordpress.sh")
  associate_public_ip_address = false

  tags = {
    Name        = "WordPressEC2"
    Environment = "dev"
    Project     = "wordpress"
  }
}

resource "aws_ebs_volume" "ebs_volume" {
  availability_zone = aws_instance.wordpress_ec2.availability_zone
  size              = 30
  type              = "gp2"
  tags = {
    Name        = "WordPressEBS"
    Environment = "dev"
    Project     = "wordpress"
  }
}

resource "aws_volume_attachment" "ebs_attachment" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.ebs_volume.id
  instance_id = aws_instance.wordpress_ec2.id
}

# RDS Instance
variable "db_instance_class" {
  type        = string
  default     = "db.t2.micro"
  description = "The instance class for the RDS instance"
}

resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version      = "8.0.23"
  instance_class      = var.db_instance_class
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password123"
  parameter_group_name = "default.mysql8.0"
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  storage_type         = "gp2"
  skip_final_snapshot  = true
  storage_encrypted    = true
  backup_retention_period = 12
  iam_database_authentication_enabled = true

  tags = {
    Name        = "WordPressDB"
    Environment = "dev"
    Project     = "wordpress"
  }
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress_db_subnet_group"
  subnet_ids = [aws_subnet.private_subnets[0].id, aws_subnet.private_subnets[1].id]

  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = [aws_subnet.public_subnets[0].id, aws_subnet.public_subnets[1].id]
  security_groups = [aws_security_group.web_server_sg.id]

  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 10
  }

  access_logs {
    bucket        = aws_s3_bucket.wordpress_bucket.id
    bucket_prefix = "elb-logs"
    interval      = 60
  }

  tags = {
    Name        = "WordPressELB"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 1
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = [aws_subnet.public_subnets[0].id, aws_subnet.public_subnets[1].id]
  load_balancers            = [aws_elb.wordpress_elb.name]

  tag {
    key                 = "Name"
    value               = "WordPressEC2"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "dev"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = "wordpress"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = "ami-0c2ab3b8efb09f272"
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_server_sg.id]
  key_name               = "wordpress-key"
  user_data              = file("./wordpress.sh")
  ebs_optimized = true

  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_s3_bucket.wordpress_bucket.bucket_regional_domain_name
    origin_id   = "wordpress-origin"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases = ["example.com"]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-origin"

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
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "sni-only"
    minimum_protocol_version = "TLSv1.2_2019"
  }

  logging_config {
    bucket = aws_s3_bucket.wordpress_bucket.id
    prefix = "cloudfront-logs"
  }

  tags = {
    Name        = "WordPressCFD"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# S3 Bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "example-bucket"
  acl    = "private"

  versioning {
    enabled = true
  }

  logging {
    target_bucket = aws_s3_bucket.wordpress_bucket.id
    target_prefix = "s3-logs/"
  }

  tags = {
    Name        = "WordPressBucket"
    Environment = "dev"
    Project     = "wordpress"
  }
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"

  tags = {
    Name        = "WordPressZone"
    Environment = "dev"
    Project     = "wordpress"
  }
}

resource "aws_route53_query_log" "wordpress_log" {
  cloudwatch_log_group_arn = aws_cloudwatch_log_group.wordpress_log_group.arn
  zone_id                  = aws_route53_zone.wordpress_zone.id
}

resource "aws_cloudwatch_log_group" "wordpress_log_group" {
  name = "wordpress-route53-logs"

  tags = {
    Name        = "WordPressRoute53Logs"
    Environment = "dev"
    Project     = "wordpress"
  }
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cfd.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cfd.zone_id
    evaluate_target_health = false
  }
}

output "vpc_id" {
  value       = aws_vpc.wordpress_vpc.id
  description = "The ID of the VPC"
}

output "subnets" {
  value       = [aws_subnet.public_subnets[0].id, aws_subnet.public_subnets[1].id, aws_subnet.private_subnets[0].id, aws_subnet.private_subnets[1].id]
  description = "The IDs of the subnets"
}

output "security_groups" {
  value       = [aws_security_group.web_server_sg.id, aws_security_group.db_sg.id]
  description = "The IDs of the security groups"
}

output "ec2_instances" {
  value       = [aws_instance.wordpress_ec2.id]
  description = "The IDs of the EC2 instances"
}

output "rds_instance" {
  value       = aws_db_instance.wordpress_db.id
  description = "The ID of the RDS instance"
}

output "elb" {
  value       = aws_elb.wordpress_elb.id
  description = "The ID of the ELB"
}

output "asg" {
  value       = aws_autoscaling_group.wordpress_asg.name
  description = "The name of the Auto Scaling Group"
}

output "cloudfront_distribution" {
  value       = aws_cloudfront_distribution.wordpress_cfd.id
  description = "The ID of the CloudFront distribution"
}

output "s3_bucket" {
  value       = aws_s3_bucket.wordpress_bucket.id
  description = "The ID of the S3 bucket"
}

output "route53_zone" {
  value       = aws_route53_zone.wordpress_zone.id
  description = "The ID of the Route 53 zone"
}
