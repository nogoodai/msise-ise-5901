terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources."
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets."
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "bastion_ami" {
  description = "AMI ID for the bastion host."
}

variable "bastion_instance_type" {
  description = "Instance type for the bastion host."
  default     = "t2.micro"
}

variable "wordpress_instance_type" {
  description = "Instance type for WordPress EC2 instances."
  default     = "t3.medium"
}

variable "rds_instance_class" {
  description = "Instance class for RDS."
  default     = "db.t2.small"
}

variable "rds_engine_version" {
  description = "Engine version for the RDS instance."
  default     = "5.7.31"  # Assuming MySQL
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = element(var.public_subnet_cidrs, count.index)
  map_public_ip_on_launch = true
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "PublicSubnet-${count.index}"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "PrivateSubnet-${count.index}"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "MainIGW"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name        = "PublicRouteTable"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = element(aws_subnet.public[*].id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id

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
    Name        = "WebServerSG"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id

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
    Name        = "RDSSG"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "bastion_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["192.168.1.1/32"]  # Change to your IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "BastionSG"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_instance" "bastion" {
  ami                         = var.bastion_ami
  instance_type               = var.bastion_instance_type
  subnet_id                   = element(aws_subnet.public[*].id, 0)
  security_groups             = [aws_security_group.bastion_sg.name]
  key_name                    = aws_key_pair.bastion_key.key_name
  associate_public_ip_address = true

  tags = {
    Name        = "BastionHost"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_key_pair" "bastion_key" {
  key_name   = "bastion-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "aws_elastic_ip" "bastion_eip" {
  instance = aws_instance.bastion.id
}

resource "aws_efs_file_system" "wordpress_efs" {
  tags = {
    Name        = "WordPressEFS"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_efs_mount_target" "wordpress_efs_mount" {
  count          = length(aws_subnet.private[*].id)
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = element(aws_subnet.private[*].id, count.index)
  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_efs_file_system_policy" "wordpress_efs_policy" {
  file_system_id = aws_efs_file_system.wordpress_efs.id
  policy         = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [{
      "Effect" : "Allow",
      "Principal" : "*",
      "Action" : "elasticfilesystem:ClientRootAccess",
      "Resource" : "*"
    }]
  })
}

resource "aws_alb" "wordpress_alb" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = {
    Name        = "WordPressALB"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_alb_listener" "http" {
  load_balancer_arn = aws_alb.wordpress_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_alb_target_group.wordpress_tg.arn
  }
}

resource "aws_alb_listener" "https" {
  load_balancer_arn = aws_alb.wordpress_alb.arn
  port              = "443"
  protocol          = "HTTPS"

  ssl_policy = "ELBSecurityPolicy-2016-08"
  certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/EXAMPLE-CERTIFICATE"

  default_action {
    type = "forward"
    target_group_arn = aws_alb_target_group.wordpress_tg.arn
  }
}

resource "aws_alb_target_group" "wordpress_tg" {
  name       = "wordpress-tg"
  port       = 80
  protocol   = "HTTP"
  vpc_id     = aws_vpc.wordpress_vpc.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name        = "WordPressTargetGroup"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  desired_capacity     = 2
  max_size             = 4
  min_size             = 2
  vpc_zone_identifier  = aws_subnet.private[*].id
  launch_configuration = aws_launch_configuration.wordpress_launch_config.id
  target_group_arns    = [aws_alb_target_group.wordpress_tg.arn]

  tag {
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress_launch_config" {
  name          = "wordpress-launch-config"
  ami           = data.aws_ami.latest_amazon_linux.id
  instance_type = var.wordpress_instance_type
  security_groups = [aws_security_group.web_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install -y php7.4
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo '<html><h1>WordPress</h1></html>' > /var/www/html/index.html
              EOF

  lifecycle {
    create_before_destroy = true
  }

  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.wordpress_instance_profile.name
}

resource "aws_iam_role" "wordpress_instance_role" {
  name = "wordpress-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com",
      },
    }],
  })
}

resource "aws_iam_policy_attachment" "wordpress_attachment" {
  name       = "wordpress-attachment"
  roles      = [aws_iam_role.wordpress_instance_role.name]
  policy_arn = aws_iam_policy.arn
}

resource "aws_iam_instance_profile" "wordpress_instance_profile" {
  role = aws_iam_role.wordpress_instance_role.name
}

resource "aws_rds_instance" "wordpress_rds" {
  identifier              = "wordpress-db"
  engine                  = "mysql"
  instance_class          = var.rds_instance_class
  allocated_storage       = 20
  name                    = "wordpress"
  username                = "admin"
  password                = random_password.db_password.result
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.wordpress.id
  skip_final_snapshot     = true

  tags = {
    Name        = "WordPressRDS"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "random_password" "db_password" {
  length  = 16
  special = true
}

resource "aws_db_subnet_group" "wordpress" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-bucket"

  versioning {
    enabled = true
  }

  tags = {
    Name        = "WordPressAssetBucket"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "wordpress-s3"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.wordpress.iam_arn
    }
  }

  enabled = true

  default_cache_behavior {
    target_origin_id       = "wordpress-s3"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]

    default_ttl = 3600
    max_ttl     = 86400

    forwarded_values {
      query_string = false
      cookies {
        forward = "all"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name        = "WordPressCloudFront"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_cloudfront_origin_access_identity" "wordpress" {
  comment = "OAI for WordPress distribution"
}

resource "aws_route53_zone" "wordpress" {
  name = "example.com"

  tags = {
    Name        = "WordPressHostedZone"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_route53_record" "wordpress" {
  zone_id = aws_route53_zone.wordpress.id
  name    = "wordpress"
  type    = "A"
  alias {
    name                   = aws_alb.wordpress_alb.dns_name
    zone_id                = aws_alb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

output "alb_dns_name" {
  description = "DNS name of the WordPress ALB"
  value       = aws_alb.wordpress_alb.dns_name
}

output "rds_endpoint" {
  description = "Endpoint of the WordPress RDS instance"
  value       = aws_rds_instance.wordpress_rds.endpoint
}

output "cloudfront_domain" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.wordpress_cf.domain_name
}
