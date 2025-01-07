# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
}

# Define variables
variable "aws_region" {
  type        = string
  default     = "us-west-2"
  description = "AWS region"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "VPC CIDR block"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "Public subnet CIDR blocks"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
  description = "Private subnet CIDR blocks"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "EC2 instance type"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
  description = "AMI ID"
}

variable "database_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "RDS instance class"
}

variable "domain_name" {
  type        = string
  description = "Domain name for Route 53"
}

# Create VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

# Create public subnets
resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = "us-west-2${count.index + 1}"
  tags = {
    Name = "PublicSubnet${count.index + 1}"
  }
}

# Create private subnets
resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = "us-west-2${count.index + 1}"
  tags = {
    Name = "PrivateSubnet${count.index + 1}"
  }
}

# Create internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Create public route table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicRouteTable"
  }
}

# Create route for public route table
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Create route table associations for public subnets
resource "aws_route_table_association" "public_subnets_associations" {
  count = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Create private route table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

# Create route table associations for private subnets
resource "aws_route_table_association" "private_subnets_associations" {
  count = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Create security groups
resource "aws_security_group" "web_server_sg" {
  name        = "WordPressWebServerSG"
  description = "Allow inbound HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

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

  tags = {
    Name = "WordPressWebServerSG"
  }
}

resource "aws_security_group" "database_sg" {
  name        = "WordPressDatabaseSG"
  description = "Allow inbound MySQL traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WordPressDatabaseSG"
  }
}

# Create EC2 instances for WordPress
resource "aws_instance" "wordpress_instances" {
  count = 2
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.web_server_sg.id
  ]
  subnet_id = aws_subnet.public_subnets[count.index].id
  key_name               = "wordpress-key"
  user_data              = file("${path.module}/wordpress.sh")
  tags = {
    Name = "WordPressInstance${count.index + 1}"
  }
}

# Create RDS instance for WordPress database
resource "aws_db_instance" "wordpress_database" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = var.database_instance_class
  name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = "wordpresspassword"
  parameter_group_name = "default.mysql8.0"
  vpc_security_group_ids = [
    aws_security_group.database_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  tags = {
    Name = "WordPressDatabase"
  }
}

# Create DB subnet group
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private_subnets.*.id

  tags = {
    Name = "WordPressDBSubnetGroup"
  }
}

# Create Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.web_server_sg.id]

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
    ssl_certificate_id = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 30
  }

  instances                   = aws_instance.wordpress_instances.*.id
  cross_zone_load_balancing = true
  idle_timeout               = 400
  connection_draining        = true
  connection_draining_timeout = 400

  tags = {
    Name = "WordPressELB"
  }
}

# Create Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "wordpress-asg"
  max_size            = 5
  min_size            = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 2
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id

  tag {
    key                 = "Name"
    value               = "WordPressASG"
    propagate_at_launch = true
  }
}

# Create Launch Configuration
resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.web_server_sg.id
  ]
  key_name               = "wordpress-key"
  user_data              = file("${path.module}/wordpress.sh")
  lifecycle {
    create_before_destroy = true
  }
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "Custom-WordPressELB"
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "Custom-WordPressELB"

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

  tags = {
    Name = "WordPressCFD"
  }

  viewer_certificate {
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "sni-only"
  }
}

# Create S3 bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-bucket"
  acl    = "private"

  versioning {
    enabled = true
  }

  tags = {
    Name = "WordPressBucket"
  }
}

# Create Route 53 record
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

# Create Route 53 zone
resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
}

# Output critical information
output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "rds_instance_address" {
  value = aws_db_instance.wordpress_database.address
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_bucket.id
}

output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cfd.domain_name
}
