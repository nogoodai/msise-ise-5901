provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

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

variable "key_name" {
  default = "wordpress-key"
}

variable "db_instance_class" {
  default = "db.t2.small"
}

variable "db_username" {
  default = "wordpress"
}

variable "db_password" {
  sensitive = true
}

variable "wordpress_bucket_name" {
  default = "wordpress-static-assets"
}

variable "cloudfront_distribution_name" {
  default = "wordpress-cloudfront-distribution"
}

variable "route53_domain_name" {
  default = "example.com"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

resource "aws_subnet" "wordpress_public_subnets" {
  count = length(var.availability_zones)
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "WordPressPublicSubnet${count.index + 1}"
  }
}

resource "aws_subnet" "wordpress_private_subnets" {
  count = length(var.availability_zones)
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, length(var.availability_zones) + count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "WordPressPrivateSubnet${count.index + 1}"
  }
}

resource "aws_route_table" "wordpress_public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name = "WordPressPublicRouteTable"
  }
}

resource "aws_route_table" "wordpress_private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressPrivateRouteTable"
  }
}

resource "aws_route_table_association" "wordpress_public_subnet_association" {
  count = length(var.availability_zones)
  subnet_id = aws_subnet.wordpress_public_subnets[count.index].id
  route_table_id = aws_route_table.wordpress_public_route_table.id
}

resource "aws_route_table_association" "wordpress_private_subnet_association" {
  count = length(var.availability_zones)
  subnet_id = aws_subnet.wordpress_private_subnets[count.index].id
  route_table_id = aws_route_table.wordpress_private_route_table.id
}

resource "aws_security_group" "wordpress_web_server_sg" {
  name        = "wordpress-web-server-sg"
  description = "Allow HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
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

resource "aws_security_group" "wordpress_db_sg" {
  name        = "wordpress-db-sg"
  description = "Allow MySQL traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "MySQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.wordpress_web_server_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WordPressDBSG"
  }
}

resource "aws_instance" "wordpress_bastion" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_web_server_sg.id]
  key_name               = var.key_name
  subnet_id              = aws_subnet.wordpress_public_subnets[0].id
  tags = {
    Name = "WordPressBastion"
  }
}

resource "aws_eip" "wordpress_bastion_eip" {
  vpc      = true
  instance = aws_instance.wordpress_bastion.id
  tags = {
    Name = "WordPressBastionEIP"
  }
}

resource "aws_efs_file_system" "wordpress_efs" {
  creation_token = "wordpress-efs"

  tags = {
    Name = "WordPressEFS"
  }
}

resource "aws_efs_mount_target" "wordpress_efs_mount_targets" {
  count = length(var.availability_zones)
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id       = aws_subnet.wordpress_private_subnets[count.index].id
  security_groups = [aws_security_group.wordpress_web_server_sg.id]
}

resource "aws_cloudwatch_metric_alarm" "wordpress_efs_alarm" {
  alarm_name                = "wordpress-efs-alarm"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = 1
  metric_name               = "BurstCreditBalance"
  namespace                 = "AWS/EFS"
  period                    = 300
  statistic                 = "Average"
  threshold                 = 100
  alarm_description         = "Alarm for EFS burst credit balance"
  actions_enabled           = true
  alarm_actions             = [aws_sns_topic.wordpress_efs_alarm_sns.arn]
}

resource "aws_sns_topic" "wordpress_efs_alarm_sns" {
  name = "wordpress-efs-alarm-sns"
}

resource "aws_elasticache_cluster" "wordpress_elasticache" {
  cluster_id           = "wordpress-elasticache"
  engine               = "memcached"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.memcached1.4"
  port                 = 11211
  subnet_group_name    = aws_elasticache_subnet_group.wordpress_elasticache_subnet_group.name
}

resource "aws_elasticache_subnet_group" "wordpress_elasticache_subnet_group" {
  name       = "wordpress-elasticache-subnet-group"
  subnet_ids = aws_subnet.wordpress_private_subnets.*.id
}

resource "aws_elasticache_security_group" "wordpress_elasticache_sg" {
  name                 = "wordpress-elasticache-sg"
  security_group_name = "wordpress-elasticache-sg"
  description         = "Allow inbound traffic to Elasticache"
  vpc_id               = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 11211
    to_port     = 11211
    protocol    = "tcp"
    security_groups = [aws_security_group.wordpress_web_server_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WordPressElasticacheSG"
  }
}

resource "aws_lb" "wordpress_alb" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.wordpress_web_server_sg.id]
  subnets            = aws_subnet.wordpress_public_subnets.*.id

  tags = {
    Name = "WordPressALB"
  }
}

resource "aws_lb_target_group" "wordpress_alb_target_group" {
  name     = "wordpress-alb-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 10
    timeout             = 5
    path                = "/"
    interval            = 10
  }

  tags = {
    Name = "WordPressALBTargetGroup"
  }
}

resource "aws_lb_listener" "wordpress_alb_listener" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.wordpress_alb_target_group.arn
    type             = "forward"
  }
}

resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version      = "8.0.23"
  instance_class       = var.db_instance_class
  name                 = "wordpressdb"
  username             = var.db_username
  password             = var.db_password
  vpc_security_group_ids = [aws_security_group.wordpress_db_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  multi_az             = true
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.wordpress_private_subnets.*.id
}

resource "aws_cloudfront_distribution" "wordpress_cloudfront_distribution" {
  origin {
    domain_name = aws_lb.wordpress_alb.dns_name
    origin_id   = "WordPressALB"
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
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
    acm_certificate_arn = aws_acm_certificate.wordpress_acm_certificate.arn
    ssl_support_method  = "sni-only"
  }
}

resource "aws_acm_certificate" "wordpress_acm_certificate" {
  domain_name       = var.route53_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = var.wordpress_bucket_name
  acl    = "private"

  tags = {
    Name = "WordPressBucket"
  }
}

resource "aws_route53_zone" "wordpress_route53_zone" {
  name = var.route53_domain_name
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.zone_id
  name    = aws_route53_zone.wordpress_route53_zone.name
  type    = "A"

  alias {
    name                   = aws_lb.wordpress_alb.dns_name
    zone_id                = aws_lb.wordpress_alb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "wordpress_cloudfront_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.zone_id
  name    = aws_route53_zone.wordpress_route53_zone.name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cloudfront_distribution.zone_id
    evaluate_target_health = false
  }
}

resource "aws_cloudwatch_log_group" "wordpress_log_group" {
  name = "wordpress-log-group"
}

resource "aws_cloudwatch_log_stream" "wordpress_log_stream" {
  name           = "wordpress-log-stream"
  log_group_name = aws_cloudwatch_log_group.wordpress_log_group.name
}

resource "aws_iam_role" "wordpress_iam_role" {
  name        = "wordpress-iam-role"
  description = "IAM role for WordPress"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
}

resource "aws_iam_policy" "wordpress_iam_policy" {
  name        = "wordpress-iam-policy"
  description = "IAM policy for WordPress"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "${aws_s3_bucket.wordpress_bucket.arn}/*"
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "wordpress_iam_role_policy_attachment" {
  role       = aws_iam_role.wordpress_iam_role.name
  policy_arn = aws_iam_policy.wordpress_iam_policy.arn
}

resource "aws_autoscaling_group" "wordpress_autoscaling_group" {
  name                = "wordpress-autoscaling-group"
  min_size            = 1
  max_size            = 10
  desired_capacity    = 1
  launch_configuration = aws_launch_configuration.wordpress_launch_configuration.name
  vpc_zone_identifier  = aws_subnet.wordpress_private_subnets.*.id

  tag {
    key                 = "Name"
    value               = "WordPressASG"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name          = "wordpress-launch-configuration"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.wordpress_web_server_sg.id]
  key_name               = var.key_name
  user_data = file("${path.module}/user-data.sh")

  lifecycle {
    create_before_destroy = true
  }
}

output "wordpress_alb_dns_name" {
  value = aws_lb.wordpress_alb.dns_name
}

output "wordpress_cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
}

output "wordpress_route53_zone_name" {
  value = aws_route53_zone.wordpress_route53_zone.name
}

output "wordpress_route53_zone_id" {
  value = aws_route53_zone.wordpress_route53_zone.zone_id
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_bucket.id
}

output "wordpress_s3_bucket_arn" {
  value = aws_s3_bucket.wordpress_bucket.arn
}

output "wordpress_db_instance_address" {
  value = aws_db_instance.wordpress_db.address
}

output "wordpress_db_instance_port" {
  value = aws_db_instance.wordpress_db.port
}

output "wordpress_db_instance_username" {
  value = aws_db_instance.wordpress_db.username
}

output "wordpress_db_instance_password" {
  value = aws_db_instance.wordpress_db.password
  sensitive = true
}

output "wordpress_iam_role_arn" {
  value = aws_iam_role.wordpress_iam_role.arn
}

output "wordpress_iam_role_name" {
  value = aws_iam_role.wordpress_iam_role.name
}

output "wordpress_autoscaling_group_name" {
  value = aws_autoscaling_group.wordpress_autoscaling_group.name
}

output "wordpress_autoscaling_group_id" {
  value = aws_autoscaling_group.wordpress_autoscaling_group.id
}
