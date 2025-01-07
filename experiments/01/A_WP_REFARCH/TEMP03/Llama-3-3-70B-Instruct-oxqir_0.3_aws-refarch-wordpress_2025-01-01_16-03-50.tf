# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Define variables for the configuration
variable "aws_region" {
  type        = string
  default     = "us-west-2"
  description = "AWS Region"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "VPC CIDR Block"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "Public Subnet CIDRs"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
  description = "Private Subnet CIDRs"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "EC2 Instance Type"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "RDS Instance Class"
}

variable "domain_name" {
  type        = string
  default     = "example.com"
  description = "Domain Name"
}

# Create a VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
  }
}

# Create public subnets
resource "aws_subnet" "public_subnets" {
  count             = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = "${var.aws_region}${count.index + 1}"
  tags = {
    Name        = "PublicSubnet${count.index + 1}"
    Environment = "production"
  }
}

# Create private subnets
resource "aws_subnet" "private_subnets" {
  count             = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = "${var.aws_region}${count.index + 1}"
  tags = {
    Name        = "PrivateSubnet${count.index + 1}"
    Environment = "production"
  }
}

# Create an internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
  }
}

# Create a public route table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = "production"
  }
}

# Create a route to the internet gateway
resource "aws_route" "public_rt_igw" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Associate public subnets with the public route table
resource "aws_route_table_association" "public_subnets" {
  count          = 2
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# Create a private route table
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = "production"
  }
}

# Associate private subnets with the private route table
resource "aws_route_table_association" "private_subnets" {
  count          = 2
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

# Create security groups
resource "aws_security_group" "wordpress_sg" {
  name        = "WordPressSG"
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
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "WordPressSG"
    Environment = "production"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "RDSSG"
  description = "Allow inbound MySQL traffic from WordPress instances"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "RDSSG"
    Environment = "production"
  }
}

# Create an RDS instance
resource "aws_db_instance" "wordpress_rds" {
  identifier        = "wordpress-rds"
  instance_class    = var.rds_instance_class
  engine            = "mysql"
  engine_version    = "8.0.23"
  username          = "wordpress"
  password          = "wordpress"
  parameter_group_name = "default.mysql8.0"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.wordpress_rds_sng.name
  storage_type           = "gp2"
  allocated_storage      = 20
  skip_final_snapshot     = true
  tags = {
    Name        = "WordPressRDS"
    Environment = "production"
  }
}

resource "aws_db_subnet_group" "wordpress_rds_sng" {
  name       = "wordpress-rds-sng"
  subnet_ids = aws_subnet.private_subnets.*.id
  tags = {
    Name        = "WordPressRDSSNG"
    Environment = "production"
  }
}

# Create an Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_sg.id]
  listener {
    lb_port       = 80
    lb_protocol   = "http"
    instance_port = 80
    instance_protocol = "http"
  }
  tags = {
    Name        = "WordPressELB"
    Environment = "production"
  }
}

# Create an Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 1
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = aws_subnet.private_subnets.*.id
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

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  security_groups = [aws_security_group.wordpress_sg.id]
  user_data = file("${path.module}/user_data.sh")
  lifecycle {
    create_before_destroy = true
  }
}

# Create a CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }
  enabled = true
  default_root_object = "index.html"
  aliases = [var.domain_name]
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.wordpress_acm.arn
    ssl_support_method  = "sni-only"
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  tags = {
    Name        = "WordPressCFD"
    Environment = "production"
  }
}

resource "aws_acm_certificate" "wordpress_acm" {
  domain_name       = var.domain_name
  validation_method = "DNS"
}

# Create an S3 bucket
resource "aws_s3_bucket" "wordpress_s3" {
  bucket = var.domain_name
  acl    = "private"
  tags = {
    Name        = "WordPressS3"
    Environment = "production"
  }
}

# Create a Route 53 record
resource "aws_route53_record" "wordpress_r53" {
  zone_id = aws_route53_zone.wordpress_r53_zone.id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cfd.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cfd.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "wordpress_r53_zone" {
  name = var.domain_name
}

# Create a CloudWatch dashboard
resource "aws_cloudwatch_dashboard" "wordpress_cwd" {
  dashboard_name = "WordPressCWD"
  dashboard_body = file("${path.module}/dashboard.json")
}

output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "wordpress_cfd_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cfd.domain_name
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3.bucket
}

output "wordpress_r53_record_name" {
  value = aws_route53_record.wordpress_r53.name
}
