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

variable "project_name" {
  type    = string
  default = "wordpress-project"
}

variable "environment" {
  type    = string
  default = "production"
}


# VPC and Networking
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "public_subnet_a" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project_name}-public-subnet-a"
    Environment = var.environment
  }
}

resource "aws_subnet" "public_subnet_b" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  tags = {
    Name        = "${var.project_name}-public-subnet-b"
    Environment = var.environment
  }
}


resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
  }
}


resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name        = "${var.project_name}-public-route-table"
    Environment = var.environment
  }
}


resource "aws_route_table_association" "public_subnet_a_association" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_b_association" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_route_table.id
}

data "aws_availability_zones" "available" {}


# Security Groups

resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow HTTP, HTTPS and SSH inbound"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] # Replace with your IP
  }


  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }


  tags = {
    Name        = "${var.project_name}-web-sg"
    Environment = var.environment
  }
}


resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow inbound traffic from web servers"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
  }
}



# EC2 Instances

resource "aws_instance" "web_server" {

  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t2.micro" # Consider appropriate instance type
  subnet_id                   = aws_subnet.public_subnet_a.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  associate_public_ip_address = true
  user_data                   = file("user_data.sh") # Add user_data file

  tags = {
    Name        = "${var.project_name}-web-server"
    Environment = var.environment
  }
}

data "aws_ami" "amazon_linux" {
 most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }


  owners = ["amazon"]
}



# RDS Instance


resource "aws_db_instance" "default" {

  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "8.0" # Update with desired version
  instance_class         = "db.t2.micro" # Consider appropriate instance class
  identifier             = "${var.project_name}-db"
  username               = "admin" # Securely manage credentials
  password                = random_password.password.result # Securely manage credentials
  db_subnet_group_name   = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true
  publicly_accessible    = false # Ensure private access


  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
  }

}

resource "aws_db_subnet_group" "default" {

  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
  }
}


resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"

}



# Elastic Load Balancer

resource "aws_lb" "web" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]

  subnets = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]


  tags = {
    Name        = "${var.project_name}-alb"
    Environment = var.environment
  }

}

resource "aws_lb_target_group" "web" {
  name        = "${var.project_name}-alb-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.wordpress_vpc.id
 target_type = "instance"

  health_check {
    path                = "/"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name        = "${var.project_name}-alb-tg"
    Environment = var.environment
  }


}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.web.arn
  port              = "80"
  protocol          = "HTTP"


  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}




# Auto Scaling


resource "aws_autoscaling_group" "web" {
  name                      = "${var.project_name}-asg"
  min_size                  = 1
  max_size                  = 3 # Adjust as per your scaling needs
  vpc_zone_identifier       = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]

  target_group_arns = [aws_lb_target_group.web.arn]
  health_check_type = "ELB"

 launch_template {

  id      = aws_launch_template.web.id
    version = "$Latest"
  }



  tag {
    key                 = "Name"
    value                = "${var.project_name}-web-server-instance"
    propagate_at_launch = true
  }


}


resource "aws_launch_template" "web" {
 name_prefix   = "${var.project_name}-launch-template"

 instance_market_options {
    market_type = "spot"
 spot_options {
      block_duration_minutes = 60
      instance_interruption_behavior = "terminate"
      max_price = "0.03" # Adjust as needed
      valid_until = "2024-01-01T00:00:00Z"
 }


  }


  image_id      = data.aws_ami.amazon_linux.id
 instance_type = "t2.micro"
  network_interfaces {


    associate_public_ip_address = true
    security_groups             = [aws_security_group.web_sg.id]


  }


  user_data = base64encode(file("user_data.sh")) # Reference your user_data script


 tag_specifications {
    resource_type = "instance"

 tag {
      key                 = "Name"
      value                = "${var.project_name}-web-server-instance"
      propagate_at_launch = true
    }

  }
}









# S3 Bucket
resource "aws_s3_bucket" "static_assets" {

  bucket = "${var.project_name}-static-assets"
 acl    = "private"


  tags = {
    Name        = "${var.project_name}-s3-bucket"
    Environment = var.environment
  }
}



# CloudFront Distribution (Example with S3 origin)
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.static_assets.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.static_assets.id

    s3_origin_config {
      origin_access_identity = "origin-access-identity/cloudfront/ABCDEFGHIJKLMN" # Replace with your OAI
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for S3 bucket"
 price_class        = "PriceClass_100"
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.static_assets.id
    viewer_protocol_policy = "redirect-to-https"



    forwarded_values {
      query_string = false


      cookies {
        forward = "none"
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
}




# Route53 (Requires a hosted zone ID)
resource "aws_route53_record" "www" {
  zone_id = var.route53_zone_id  # Replace with your hosted zone ID
  name    = "www." # Example, adjust as needed
  type    = "A"




  alias {
    name                   = aws_lb.web.dns_name
    zone_id                = aws_lb.web.zone_id
    evaluate_target_health = true
  }
}


variable "route53_zone_id" {
  type = string
 description = "The Route53 Zone ID"
}






output "alb_dns_name" {
 value = aws_lb.web.dns_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.static_assets.bucket

}


output "cloudfront_domain_name" {
 value = aws_cloudfront_distribution.s3_distribution.domain_name
}


output "rds_endpoint" {
 value = aws_db_instance.default.endpoint
}

