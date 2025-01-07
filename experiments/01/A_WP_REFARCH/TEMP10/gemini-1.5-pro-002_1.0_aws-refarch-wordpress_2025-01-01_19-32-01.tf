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
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags = {
    Name        = "${var.project_name}-public-subnet-a"
    Environment = var.environment
    Project     = var.project_name
  }

}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project_name}-private-subnet-a"
    Environment = var.environment
    Project     = var.project_name
  }
}



resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name        = "${var.project_name}-public-route-table"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}


resource "aws_route_table" "private" {
 vpc_id = aws_vpc.main.id
 tags = {
    Name        = "${var.project_name}-private-route-table"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

data "aws_availability_zones" "available" {}


# Security Groups

resource "aws_security_group" "web_server_sg" {
  name        = "${var.project_name}-web-server-sg"
  description = "Allow HTTP, HTTPS, and SSH inbound"
  vpc_id      = aws_vpc.main.id

 ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Replace with your IP or CIDR range
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }


  tags = {
    Name        = "${var.project_name}-web-server-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}



resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow inbound traffic from web servers"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
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
    Project     = var.project_name
  }
}




# EC2 Instances and Auto Scaling

resource "aws_launch_template" "wordpress_lt" {
 name_prefix   = "${var.project_name}-wordpress-lt-"
 image_id      = data.aws_ami.amazon_linux_2.id
 instance_type = "t2.micro"
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web_server_sg.id]
    subnet_id = aws_subnet.public_a.id
  }
  user_data = filebase64("./user_data.sh") # Replace with your user data

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.project_name}-wordpress-lt"
    Environment = var.environment
    Project     = var.project_name
  }

}



data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}


resource "aws_autoscaling_group" "wordpress_asg" {

  name                      = "${var.project_name}-asg"
  launch_template {
    id      = aws_launch_template.wordpress_lt.id
    version = "$Latest"
 }
  min_size                  = 1
  max_size                  = 3
 vpc_zone_identifier = [aws_subnet.public_a.id]
  health_check_grace_period = 300

  tags = {
    Name        = "${var.project_name}-asg"
    Environment = var.environment
    Project     = var.project_name
  }
}


# RDS Instance

resource "aws_db_instance" "wordpress_db" {
  identifier              = "${var.project_name}-db"
  allocated_storage      = 20
  storage_type           = "gp2"

  engine                 = "mysql"
  engine_version        = "8.0.32" # Example version
  instance_class         = "db.t2.micro"
  username               = "admin" # Replace with your username
  password               = random_password.rds_password.result # Use generated password
  db_subnet_group_name   = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true

  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
    Project     = var.project_name
  }

}


resource "random_password" "rds_password" {
  length = 16
  special = true
}

resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id]

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
    Project     = var.project_name
  }
}





# Load Balancer

resource "aws_lb" "wordpress_lb" {
  name               = "${var.project_name}-lb"

  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_server_sg.id]

  subnets = [aws_subnet.public_a.id]


  tags = {
    Name        = "${var.project_name}-alb"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lb_target_group" "wordpress_tg" {
  name        = "${var.project_name}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"



  health_check {
    path                = "/"
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}


resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress_lb.arn
  port              = "80"
  protocol          = "HTTP"


  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}


resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.wordpress_asg.name
  alb_target_group_arn   = aws_lb_target_group.wordpress_tg.arn
}



# S3 Bucket


resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "${var.project_name}-bucket"
  acl    = "private"


  tags = {
    Name        = "${var.project_name}-s3-bucket"
    Environment = var.environment
    Project     = var.project_name
  }
}



# CloudFront Distribution (Basic Example -  Configure as needed )

resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_lb.wordpress_lb.dns_name
    origin_id   = "albOrigin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # or "match-viewer"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

 enabled             = true
  is_ipv6_enabled     = true
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "albOrigin"

 viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl           = 3600
    max_ttl                = 86400
  }


  price_class = "PriceClass_All"


  viewer_certificate {
    cloudfront_default_certificate = true
  }



  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }


  tags = {
    Name        = "${var.project_name}-cloudfront"
    Environment = var.environment
    Project     = var.project_name
  }
}


# Route53 (Example - Requires a hosted zone ID.  Configure based on your DNS setup)


# Example (Assumes a pre-existing hosted zone) - Replace with your hosted zone ID and domain
resource "aws_route53_record" "wordpress_record" {
 # zone_id = "YOUR_HOSTED_ZONE_ID" # Replace with your Hosted Zone ID.
  name    = "wordpress.${var.project_name}.com"  # Replace with your desired domain/subdomain.
 type    = "A"
 alias {
    name                   = aws_cloudfront_distribution.wordpress_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cdn.hosted_zone_id
    evaluate_target_health = false
  }
}


output "load_balancer_dns_name" {
  value = aws_lb.wordpress_lb.dns_name
}

output "cloudfront_domain_name" {
 value = aws_cloudfront_distribution.wordpress_cdn.domain_name

}

output "rds_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_bucket.bucket
}

