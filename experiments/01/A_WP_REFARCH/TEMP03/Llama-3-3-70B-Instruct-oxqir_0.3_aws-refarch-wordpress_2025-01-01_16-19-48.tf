# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Define variables for the configuration
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  default = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "instance_type" {
  default = "t2.micro"
}

variable "ami_id" {
  default = "ami-0c94855ba95c71c99"
}

variable "database_instance_class" {
  default = "db.t2.small"
}

variable "database_engine" {
  default = "mysql"
}

variable "elasticache_node_type" {
  default = "cache.t2.micro"
}

variable "elasticache_engine" {
  default = "memcached"
}

variable "cloudfront_ssl_certificate" {
  default = "arn:aws:iam::123456789012:server-certificate/cloudfront-ssl-certificate"
}

variable "route53_domain_name" {
  default = "example.com"
}

# Create a VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

# Create public and private subnets
resource "aws_subnet" "public_subnets" {
  count = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PublicSubnet${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, length(var.availability_zones) + count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PrivateSubnet${count.index + 1}"
  }
}

# Create an internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Create public and private route tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

# Create routes for public route table
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public_subnets_association" {
  count = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Associate private subnets with private route table
resource "aws_route_table_association" "private_subnets_association" {
  count = length(var.availability_zones)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Create security groups
resource "aws_security_group" "web_server_sg" {
  name        = "WebServerSG"
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
    Name = "WebServerSG"
  }
}

resource "aws_security_group" "database_sg" {
  name        = "DatabaseSG"
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
    Name = "DatabaseSG"
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
  tags = {
    Name = "WordPressInstance${count.index + 1}"
  }
}

# Create RDS instance for WordPress database
resource "aws_db_instance" "wordpress_database" {
  allocated_storage    = 20
  engine               = var.database_engine
  engine_version       = "8.0.23"
  instance_class       = var.database_instance_class
  name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = "wordpresspassword"
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
  name       = "wordpressdb-subnet-group"
  subnet_ids = aws_subnet.private_subnets.*.id
  tags = {
    Name = "WordPressDBSubnetGroup"
  }
}

# Create Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.web_server_sg.id]
  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
  tags = {
    Name = "WordPressELB"
  }
}

# Create Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  max_size                  = 5
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id
  tags = [
    {
      key                 = "Name"
      value               = "WordPressASG"
      propagate_at_launch = true
    },
  ]
}

# Create Launch Configuration for Auto Scaling Group
resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.web_server_sg.id
  ]
  user_data = file("${path.module}/wordpress-user-data.sh")
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }
  enabled = true
  default_root_object = "index.html"
  aliases = [var.route53_domain_name]
  viewer_certificate {
    acm_certificate_arn = var.cloudfront_ssl_certificate
    ssl_support_method  = "sni-only"
  }
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WordPressELB"
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
}

# Create S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = var.route53_domain_name
  acl    = "private"
  tags = {
    Name = "WordPressS3Bucket"
  }
}

# Create Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_route53_zone" {
  name = var.route53_domain_name
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name    = var.route53_domain_name
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = true
  }
}

# Create CloudWatch logs and alarms
resource "aws_cloudwatch_log_group" "wordpress_log_group" {
  name = "WordPressLogGroup"
}

resource "aws_cloudwatch_log_stream" "wordpress_log_stream" {
  name           = "WordPressLogStream"
  log_group_name = aws_cloudwatch_log_group.wordpress_log_group.name
}

resource "aws_cloudwatch_metric_alarm" "wordpress_alarm" {
  alarm_name                = "WordPressAlarm"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = "2"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "300"
  statistic                  = "Average"
  threshold                 = "80"
  alarm_description         = "This metric alarm monitors the CPU utilization of the WordPress instances"
  alarm_actions             = [aws_sns_topic.wordpress_sns_topic.arn]
  insufficient_data_actions = []
  ok_actions                = []
}

# Create SNS topic for alarm notifications
resource "aws_sns_topic" "wordpress_sns_topic" {
  name = "WordPressSNSTopic"
}

# Create IAM roles and policies for EC2 instances
resource "aws_iam_role" "wordpress_ec2_role" {
  name        = "WordPressEC2Role"
  description = "IAM role for WordPress EC2 instances"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "wordpress_ec2_policy" {
  name        = "WordPressEC2Policy"
  description = "IAM policy for WordPress EC2 instances"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
        ]
        Effect = "Allow"
        Resource = aws_s3_bucket.wordpress_s3_bucket.arn
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "wordpress_ec2_policy_attachment" {
  role       = aws_iam_role.wordpress_ec2_role.name
  policy_arn = aws_iam_policy.wordpress_ec2_policy.arn
}

# Output critical information
output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "subnet_ids" {
  value = aws_subnet.public_subnets.*.id
}

output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "rds_instance_endpoint" {
  value = aws_db_instance.wordpress_database.endpoint
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.wordpress_cfd.id
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3_bucket.id
}

output "route53_zone_id" {
  value = aws_route53_zone.wordpress_route53_zone.id
}
