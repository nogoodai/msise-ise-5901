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
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project_name}-public-subnet-1"
    Environment = var.environment
  }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project_name}-private-subnet-1"
    Environment = var.environment
  }
}


data "aws_availability_zones" "available" {}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
  }
}


resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name        = "${var.project_name}-public-route-table"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public_subnet_association" {
 subnet_id      = aws_subnet.public_1.id
 route_table_id = aws_route_table.public_route_table.id
}



# Security Groups
resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow inbound HTTP, HTTPS, and SSH"
  vpc_id      = aws_vpc.main.id

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
  description = "Allow inbound MySQL/Aurora from web servers"
 vpc_id = aws_vpc.main.id

 ingress {
    from_port = 3306
 to_port   = 3306
    protocol  = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }
 tags = {
    Name = "${var.project_name}-rds-sg"
 Environment = var.environment
  }
}


# EC2 Instances (Web Servers)

resource "aws_instance" "web_server" {

  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  subnet_id = aws_subnet.public_1.id

  vpc_security_group_ids = [aws_security_group.web_sg.id]
 user_data = <<EOF
#!/bin/bash
sudo yum update -y
sudo amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2
sudo yum install -y httpd mariadb-server
sudo systemctl start httpd
sudo systemctl enable httpd
sudo systemctl start mariadb
sudo systemctl enable mariadb
EOF


 tags = {
    Name        = "${var.project_name}-web-server"
    Environment = var.environment
  }

}

data "aws_ami" "amazon_linux" {

 most_recent = true
 owners      = ["amazon"]

 filter {
    name   = "name"
 values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}



# RDS Instance
resource "aws_db_instance" "default" {

  allocated_storage    = 20
  storage_type        = "gp2"
  engine              = "mysql"
  engine_version      = "8.0"
  instance_class      = "db.t2.micro"
  name                = "wordpress"
  username            = "admin" # Replace with a secure password
  password            = "password" # Replace with a secure password
  parameter_group_name= "default.mysql8.0"
  skip_final_snapshot = true
 db_subnet_group_name = aws_db_subnet_group.default.name
 vpc_security_group_ids = [aws_security_group.rds_sg.id]

  tags = {
    Name        = "${var.project_name}-rds"
 Environment = var.environment
  }

}


resource "aws_db_subnet_group" "default" {

  name       = "${var.project_name}-db-subnet-group"
 subnet_ids = [aws_subnet.private_1.id]

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
  }
}


# Elastic Load Balancer
resource "aws_lb" "web" {
 name               = "${var.project_name}-lb"
 internal           = false
 load_balancer_type = "application"
 security_groups    = [aws_security_group.web_sg.id]
 subnets            = [aws_subnet.public_1.id]

  tags = {
    Name        = "${var.project_name}-lb"
    Environment = var.environment
  }
}


resource "aws_lb_listener" "http" {
 load_balancer_arn = aws_lb.web.arn
 port              = "80"
 protocol          = "HTTP"


  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}




resource "aws_lb_target_group" "web" {

 name     = "${var.project_name}-lb-tg"
 port     = 80
 protocol = "HTTP"
 vpc_id   = aws_vpc.main.id


 health_check {
    path = "/"
  }
}



resource "aws_lb_target_group_attachment" "web" {
 target_group_arn = aws_lb_target_group.web.arn
 target_id        = aws_instance.web_server.id
 port             = 80

}



# Autoscaling Group
resource "aws_autoscaling_group" "web" {
 name                 = "${var.project_name}-asg"
 vpc_zone_identifier = [aws_subnet.public_1.id]
 launch_configuration = aws_launch_configuration.web.name
 min_size             = 1
 max_size             = 2
 health_check_type = "ELB"
 target_group_arns  = [aws_lb_target_group.web.arn]

 tag {

    key                 = "Name"
    value              = "${var.project_name}-asg-instance"
    propagate_at_launch = true

  }

}

resource "aws_launch_configuration" "web" {
 name_prefix                 = "${var.project_name}-lc"
 image_id                    = data.aws_ami.amazon_linux.id
 instance_type               = "t2.micro"
 security_groups             = [aws_security_group.web_sg.id]
 user_data = <<EOF
#!/bin/bash
sudo yum update -y
sudo amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2
sudo yum install -y httpd mariadb-server
sudo systemctl start httpd
sudo systemctl enable httpd
sudo systemctl start mariadb
sudo systemctl enable mariadb
EOF


 lifecycle {
 create_before_destroy = true
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



# CloudFront Distribution (Basic -  Integrate with S3 or ALB later)
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {

    domain_name = aws_s3_bucket.static_assets.bucket_regional_domain_name
 origin_id   = aws_s3_bucket.static_assets.bucket

    s3_origin_config {
      origin_access_identity = "" # Update with an OAI if needed for private bucket access
    }

  }


 enabled             = true
 is_ipv6_enabled     = true
  comment             = "CloudFront distribution for S3 bucket"
  default_root_object = "index.html"

  default_cache_behavior {


 allowed_methods  = ["GET", "HEAD"]
    cached_methods = ["GET", "HEAD"]
 target_origin_id = aws_s3_bucket.static_assets.bucket
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
 default_ttl               = 3600
    max_ttl                = 86400

  }

 price_class = "PriceClass_100"


 restrictions {

    geo_restriction {
      restriction_type = "none"
    }

 }

  viewer_certificate {

    cloudfront_default_certificate = true
  }

}



# Route53 (Placeholder - Requires a hosted zone ID)
# resource "aws_route53_record" "www" {
#  zone_id = "YOUR_HOSTED_ZONE_ID"  # Replace with your hosted zone ID
#  name    = "www.${var.domain_name}" # Replace with your domain name
#  type    = "A"


#  alias {

#    name                   = aws_lb.web.dns_name
#    zone_id                = aws_lb.web.zone_id
#    evaluate_target_health = true
#  }
# }





output "vpc_id" {
 value = aws_vpc.main.id
}

output "load_balancer_dns_name" {
  value = aws_lb.web.dns_name
}

output "s3_bucket_arn" {
 value = aws_s3_bucket.static_assets.arn
}

output "rds_endpoint" {
  value = aws_db_instance.default.endpoint
}


