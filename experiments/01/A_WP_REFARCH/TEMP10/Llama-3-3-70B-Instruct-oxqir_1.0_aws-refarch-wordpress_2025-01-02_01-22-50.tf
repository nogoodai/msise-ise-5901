# Configure the AWS provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
}

# VPC configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "WordPressVPC"
  }
}

# Create subnets
resource "aws_subnet" "public_subnets" {
  count = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "PublicSubnet${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, count.index + 2)
  availability_zone = data.aws_availability_zones.available.names[count.index]
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

# Create route tables
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

# Create route table associations
resource "aws_route_table_association" "public_subnets" {
  count = 2
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnets" {
  count = 2
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Create public route
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Create security groups
resource "aws_security_group" "web_server_sg" {
  name        = "WordPressWebServerSG"
  description = "Allow HTTP and HTTPS traffic"
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

resource "aws_security_group" "rds_sg" {
  name        = "WordPressRDSSG"
  description = "Allow MySQL traffic"
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
    Name = "WordPressRDSSG"
  }
}

# Create RDS instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = "db.t2.small"
  name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = "wordpresspassword"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.wordpress_rds_sg.name
  parameter_group_name = aws_db_parameter_group.wordpress_rds_pg.name
  multi_az             = true
  backup_retention_period = 30
}

# Create RDS parameter group
resource "aws_db_parameter_group" "wordpress_rds_pg" {
  name        = "wordpress-rds-pg"
  family      = "mysql8.0"
  description = "RDS parameter group for WordPress"
}

# Create RDS subnet group
resource "aws_db_subnet_group" "wordpress_rds_sg" {
  name       = "wordpress-rds-sg"
  subnet_ids = aws_subnet.private_subnets.*.id
}

# Create EC2 instances
resource "aws_instance" "wordpress_ec2" {
  count = 2
  ami           = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  subnet_id = aws_subnet.public_subnets[count.index].id
  key_name               = "wordpress-ec2-key"
  tags = {
    Name = "WordPressEC2${count.index + 1}"
  }
}

# Create Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
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

  tags = {
    Name = "WordPressELB"
  }
}

# Create Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  max_size                  = 5
  min_size                  = 2
  desired_size             = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  launch_configuration      = aws_launch_configuration.wordpress_lcfg.name
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id
}

# Create Launch Configuration
resource "aws_launch_configuration" "wordpress_lcfg" {
  name          = "WordPressLCFG"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.web_server_sg.id]
  key_name               = "wordpress-ec2-key"
  user_data = <<-EOF
              #!/bin/bash
              sudo apt update
              sudo apt install -y apache2
              sudo systemctl start apache2
              sudo systemctl enable apache2
              EOF
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-elb"

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

# Create S3 bucket
resource "aws_s3_bucket" "wordpress_s3" {
  bucket        = "wordpress-s3-bucket"
  force_destroy = true
  tags = {
    Name = "WordPressS3"
  }
}

# Create Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_r53" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress_r53_record" {
  zone_id = aws_route53_zone.wordpress_r53.id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = true
  }
}

# Create CloudWatch logs and metrics
resource "aws_cloudwatch_log_group" "wordpress_cwlg" {
  name = "wordpress-cwlg"
}

resource "aws_cloudwatch_metric_alarm" "wordpress_cwma" {
  alarm_name          = "wordpress-cwma"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  actions_enabled     = true
  alarm_actions       = [aws_sns_topic.wordpress_sns.arn]
}

resource "aws_sns_topic" "wordpress_sns" {
  name = "wordpress-sns"
}

resource "aws_sns_topic_subscription" "wordpress_sns_subscription" {
  topic_arn = aws_sns_topic.wordpress_sns.arn
  protocol  = "email"
  endpoint  = "example@example.com"
}

# Create EFS file system
resource "aws_efs_file_system" "wordpress_efs" {
  creation_token = "wordpress-efs"

  tags = {
    Name = "WordPressEFS"
  }
}

# Create EFS mount targets
resource "aws_efs_mount_target" "wordpress_efs_mt" {
  count = 2
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = aws_subnet.private_subnets[count.index].id
  security_groups = [aws_security_group.web_server_sg.id]
}

# Create Elasticache cluster
resource "aws_elasticache_cluster" "wordpress_ec" {
  cluster_id           = "wordpress-ec"
  engine               = "memcached"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.memcached1.4"
  port                 = 11211
  subnet_group_name    = aws_elasticache_subnet_group.wordpress_ec_sg.name
  security_group_ids   = [aws_security_group.web_server_sg.id]
}

# Create Elasticache subnet group
resource "aws_elasticache_subnet_group" "wordpress_ec_sg" {
  name       = "wordpress-ec-sg"
  subnet_ids = aws_subnet.private_subnets.*.id
}

output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_cfd_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cfd.domain_name
}

output "wordpress_r53_record_name" {
  value = aws_route53_record.wordpress_r53_record.name
}
