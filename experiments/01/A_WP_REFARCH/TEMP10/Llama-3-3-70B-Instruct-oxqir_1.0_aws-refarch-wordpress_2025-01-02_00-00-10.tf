provider "aws" {
  region = "us-west-2"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-west-2a", "us-west-2b"]
}

variable "instance_type" {
  default = "t2.micro"
}

variable "ami_id" {
  default = "ami-0c94855ba95c71c99"
}

variable "db_instance_class" {
  default = "db.t2.small"
}

variable "wordpress_version" {
  default = "latest"
}

variable "admin_cidr_blocks" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "ssh_cidr_blocks" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

# Create VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr

  tags = {
    Name        = "WordPressVPC"
    Environment = "Production"
  }
}

# Create public subnets
resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnet_cidrs)

  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name        = "WordPressPublicSubnet${count.index + 1}"
    Environment = "Production"
  }
}

# Create private subnets
resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name        = "WordPressPrivateSubnet${count.index + 1}"
    Environment = "Production"
  }
}

# Create internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "WordPressIGW"
    Environment = "Production"
  }
}

# Create public route table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "WordPressPublicRT"
    Environment = "Production"
  }
}

resource "aws_route" "public_rt_igw" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block  = "0.0.0.0/0"
  gateway_id              = aws_internet_gateway.wordpress_igw.id
}

# Create private route table
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "WordPressPrivateRT"
    Environment = "Production"
  }
}

# Associate subnets with route tables
resource "aws_route_table_association" "public_rta" {
  count = length(aws_subnet.public_subnets)

  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_rta" {
  count = length(aws_subnet.private_subnets)

  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

# Create security groups
resource "aws_security_group" "web_sg" {
  name        = "WordPressWebSG"
  description = "Security group for WordPress web servers"
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
    cidr_blocks = var.admin_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WordPressWebSG"
    Environment = "Production"
  }
}

resource "aws_security_group" "db_sg" {
  name        = "WordPressDBSG"
  description = "Security group for WordPress database"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WordPressDBSG"
    Environment = "Production"
  }
}

# Create RDS instance
resource "aws_db_instance" "wordpress_db" {
  instance_class = var.db_instance_class
  engine         = "mysql"
  username       = "wordpress"
  password       = "wordpress_password"
  db_name         = "wordpress_db"

  vpc_security_group_ids = [aws_security_group.db_sg.id]

  tags = {
    Name        = "WordPressDB"
    Environment = "Production"
  }
}

# Create EC2 instances
resource "aws_instance" "wordpress_ec2" {
  ami           = var.ami_id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  subnet_id = aws_subnet.public_subnets[0].id

  key_name = "wordpress-key"

  tags = {
    Name        = "WordPressEC2"
    Environment = "Production"
  }
}

# Create Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = [aws_subnet.public_subnets[0].id, aws_subnet.public_subnets[1].id]
  security_groups = [aws_security_group.web_sg.id]

  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 80
    lb_protocol        = "http"
  }

  tags = {
    Name        = "WordPressELB"
    Environment = "Production"
  }
}

# Create Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                 = "WordPressASG"
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  min_size             = 1
  max_size             = 3
  vpc_zone_identifier  = aws_subnet.public_subnets[0].id

  tags = [
    {
      key                 = "Name"
      value               = "WordPressEC2"
      propagate_at_launch = true
    },
  ]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_sg.id]

  lifecycle {
    create_before_destroy = true
  }
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressOrigin"
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WordPressOrigin"

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

  tags = {
    Name        = "WordPressCFD"
    Environment = "Production"
  }
}

# Create S3 bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-bucket"
  acl    = "private"

  tags = {
    Name        = "WordPressS3Bucket"
    Environment = "Production"
  }
}

# Create Route 53 DNS configuration
resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "www.example.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cfd.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cfd.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
}

resource "aws_efs_file_system" "wordpress_efs" {
  creation_token = "wordpress-efs"

  tags = {
    Name        = "WordPressEFS"
    Environment = "Production"
  }
}

resource "aws_efs_mount_target" "wordpress_efs_mount" {
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = aws_subnet.private_subnets[0].id
}

resource "aws_cloudwatch_metric_alarm" "wordpress_efs_alarm" {
  alarm_name                = "WordPressEFSSpaceAlarm"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = "2"
  metric_name               = "FreeStorageSpace"
  namespace                 = "AWS/EFS"
  period                    = "300"
  statistic                 = "Average"
  threshold                = "10"
  alarm_description         = "Alarm for low free storage space"
  actions_enabled          = true
  alarm_actions            = []
  insufficient_data_actions = []
  ok_actions               = []
  treat_missing_data       = "missing"

  metric_query {
    id          = "metric1"
    metric {
      metric_name = "FreeStorageSpace"
      namespace   = "AWS/EFS"
      unit        = "Gigabytes"
    }
  }
}

# Outputs
output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_bucket_name" {
  value = aws_s3_bucket.wordpress_bucket.bucket
}

output "wordpress_efs_id" {
  value = aws_efs_file_system.wordpress_efs.id
}
