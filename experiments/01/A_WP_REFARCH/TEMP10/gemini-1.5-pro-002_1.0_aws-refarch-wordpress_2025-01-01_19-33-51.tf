terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "domain_name" {
  type    = string
  default = "example.com"
}



resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "wordpress-vpc"
    Environment = "production"
  }
}

resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  cidr_block        = var.public_subnet_cidrs[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name        = "wordpress-public-subnet-${count.index}"
    Environment = "production"

  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  cidr_block        = var.private_subnet_cidrs[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name        = "wordpress-private-subnet-${count.index}"
    Environment = "production"
  }
}


data "aws_availability_zones" "available" {}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "wordpress-igw"
    Environment = "production"

  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "wordpress-public-route-table"
    Environment = "production"

  }
}


resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table_association" "public_subnet_association" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}


resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "wordpress-private-route-table"
    Environment = "production"

  }
}

resource "aws_route_table_association" "private_subnet_association" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}



resource "aws_security_group" "web_sg" {
 name = "wordpress-web-sg"
  description = "Allow HTTP, HTTPS and SSH access"
  vpc_id      = aws_vpc.wordpress_vpc.id

 ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description      = "SSH from my IP"
    from_port        = 22
    to_port          = 22
    protocol        = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] # Replace with your public IP
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol        = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name        = "wordpress-web-sg"
    Environment = "production"
  }

}

resource "aws_security_group" "db_sg" {
  name = "wordpress-db-sg"
  description = "Allow MySQL access from web servers"
  vpc_id = aws_vpc.wordpress_vpc.id

 ingress {
 from_port = 3306
 to_port = 3306
 protocol = "tcp"
 security_groups = [aws_security_group.web_sg.id]
 }

  egress {
    from_port = 0
 to_port = 0
 protocol = "-1"
 cidr_blocks = ["0.0.0.0/0"]
 ipv6_cidr_blocks = ["::/0"]
 }

 tags = {
 Name = "wordpress-db-sg"
 Environment = "production"
 }
}


resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private_subnets[*].id

  tags = {
    Name = "wordpress-db-subnet-group"
 Environment = "production"
  }
}

resource "aws_db_instance" "wordpress_db" {

  identifier = "wordpress-db"
 allocated_storage = 20
  storage_type = "gp2"
  engine = "mysql"
  engine_version = "8.0.32" # Use a supported version
  instance_class = var.db_instance_class
  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.name
  username = "admin" # Replace with your username
  password = "password123" # Replace with a strong password
  skip_final_snapshot = true
  publicly_accessible = false
  vpc_security_group_ids = [aws_security_group.db_sg.id]
 multi_az = false  # Enable for high availability


  tags = {
    Name = "wordpress-db"
    Environment = "production"

  }

}



resource "aws_lb" "wordpress_alb" {

  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = aws_subnet.public_subnets[*].id


  tags = {
 Name = "wordpress-alb"
    Environment = "production"
  }
}

resource "aws_lb_listener" "http" {

  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = "80"
  protocol          = "HTTP"


  default_action {
    type             = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}


resource "aws_lb_listener" "https" {
 load_balancer_arn = aws_lb.wordpress_alb.arn
  port            = "443"
  protocol        = "HTTPS"
  ssl_policy     = "ELBSecurityPolicy-TLS-1-2-Ext-2018-06" # Choose an appropriate SSL policy

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
 }

  certificate_arn = "arn:aws:iam::xxxxxxxxxxxx:server-certificate/test_cert" # Replace or create your certificate
}


resource "aws_lb_target_group" "wordpress_tg" {

  name        = "wordpress-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.wordpress_vpc.id
  target_type = "instance"

 health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

}




resource "aws_launch_template" "wordpress_lt" {
  name_prefix   = "wordpress-lt-"
  image_id      = "ami-0c94855ba95c574c8" # Replace with a suitable AMI
 instance_type = var.instance_type
  user_data = filebase64("user_data.sh") # Create this file with your WordPress setup script
  iam_instance_profile {
    name = aws_iam_instance_profile.wordpress_profile.name
  }
  network_interfaces {
    security_groups = [aws_security_group.web_sg.id]
    associate_public_ip_address = true
    subnet_id = aws_subnet.public_subnets[0].id # Use a public subnet
  }
 tag_specifications {
    resource_type = "instance"
    tags = {
 Name = "wordpress-instance"
 Environment = "production"
 }
 }
}


resource "aws_autoscaling_group" "wordpress_asg" {

  name                 = "wordpress-asg"
  min_size             = 2
  max_size             = 4
  vpc_zone_identifier  = aws_subnet.public_subnets[*].id
  launch_template {
    id      = aws_launch_template.wordpress_lt.id
    version = "$Latest"
  }


  health_check_type = "ELB"
  target_group_arns = [aws_lb_target_group.wordpress_tg.arn]

  tag {
 key                 = "Name"
    value               = "wordpress-asg"
    propagate_at_launch = true
  }
  tag {
 key                 = "Environment"
 value = "production"
 propagate_at_launch = true

  }

}



resource "aws_lb_attachment" "wordpress_attachment" {
  target_group_arn = aws_lb_target_group.wordpress_tg.arn
  autoscaling_group_name = aws_autoscaling_group.wordpress_asg.name
}


resource "aws_iam_role" "wordpress_role" {

  name = "wordpress-role"


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


resource "aws_iam_policy" "wordpress_policy" {

 name = "wordpress-policy"


 policy = jsonencode({
    Version = "2012-10-17",
 Statement = [

      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
 ],
        Resource = [
 "*"
        ]
 },
      {
        Effect = "Allow",
        Action = [
 "elasticfilesystem:ClientMount",
 "elasticfilesystem:ClientWrite",
 "elasticfilesystem:DescribeFileSystems"
 ],
        Resource = "*"
      }


    ]
 })

}


resource "aws_iam_policy_attachment" "wordpress_policy_attachment" {
 name       = "wordpress-policy-attachment"
  roles      = [aws_iam_role.wordpress_role.name]
  policy_arn = aws_iam_policy.wordpress_policy.arn
}


resource "aws_iam_instance_profile" "wordpress_profile" {
 name = "wordpress-instance-profile"
 role = aws_iam_role.wordpress_role.name
}



resource "aws_s3_bucket" "wordpress_bucket" {

  bucket = "wordpress-bucket-${random_id.bucket_id.hex}"
  acl    = "private" # Restrict access based on your requirements

 tags = {
 Name = "wordpress-bucket"
    Environment = "production"
  }
}

resource "random_id" "bucket_id" {
  byte_length = 8
}




resource "aws_cloudfront_distribution" "wordpress_cdn" {

  origin {
 domain_name = aws_lb.wordpress_alb.dns_name
    origin_id   = "wordpress-alb"
 custom_origin_config {
 HTTP_port = 80
 HTTPS_port = 443
 origin_protocol_policy = "http-only" # Or "https-only" depending on your ALB setup
 }
 }


  enabled             = true
  is_ipv6_enabled     = true
  comment             = "WordPress CDN"
  default_root_object = "index.html"


  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
 target_origin_id = "wordpress-alb"
    viewer_protocol_policy = "redirect-to-https"

 forwarded_values {
      query_string = false

 cookies {
 forward = "none"
 }
    }

 min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true

  }

 price_class = "PriceClass_100" # Select the appropriate price class


  restrictions {
    geo_restriction {
      restriction_type = "none" # Customize as needed
    }
 }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}




resource "aws_route53_zone" "wordpress_zone" {

  name = var.domain_name

  tags = {
 Name = "wordpress-zone"
    Environment = "production"
  }
}


resource "aws_route53_record" "wordpress_record" {

  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.domain_name
 type    = "A"


  alias {
    name                   = aws_cloudfront_distribution.wordpress_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cdn.hosted_zone_id
    evaluate_target_health = false
  }
}


output "alb_dns_name" {
  value = aws_lb.wordpress_alb.dns_name
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cdn.domain_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_bucket.bucket
}
output "rds_endpoint" {
 value = aws_db_instance.wordpress_db.endpoint
}
