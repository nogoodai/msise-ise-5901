terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type        = string
  description = "The AWS region to deploy into."
  default     = "us-west-2"
}

variable "project_name" {
  type        = string
  description = "The name of the project."
  default     = "wordpress-project"
}

variable "environment" {
  type        = string
  description = "The environment name (e.g., production, development)."
  default     = "production"
}

variable "admin_ip" {
  type        = string
  description = "The IP address allowed to SSH into the web server."
  default     = "0.0.0.0/0" # Default to allow all, but should be restricted in production.
}



variable "db_username" {
  type        = string
  description = "The database username."
  default     = null

}

variable "db_password" {
  type        = string
  description = "The database password."
  default     = null
  sensitive   = true
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

resource "aws_route_table" "public" {
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

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}


# Security Groups
resource "aws_security_group" "web_server_sg" {
  name        = "${var.project_name}-web-server-sg"
  description = "Allow HTTP, HTTPS and SSH inbound"
  vpc_id      = aws_vpc.main.id


  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] # Open to all for now, restrict in production
    description      = "Allow HTTP traffic from anywhere"

  }

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] # Open to all for now, restrict in production
    description      = "Allow HTTPS traffic from anywhere"

  }

 ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
    description = "Allow SSH traffic from admin"
  }


  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
    description      = "Allow all outbound traffic"
  }


  tags = {
    Name        = "${var.project_name}-web-server-sg"
    Environment = var.environment
  }
}


resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow inbound traffic from web servers"
  vpc_id      = aws_vpc.main.id



  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
 description = "Allow MySQL traffic from web servers"
  }


  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
 description = "Allow all outbound traffic"
  }



  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
  }
}


# EC2 Instances and Auto Scaling
resource "aws_instance" "web_server" {
  ami                    = "ami-0c94855ba95c574c8" # Replace with your desired AMI
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  user_data              = <<-EOF
#!/bin/bash
sudo yum update -y
sudo yum install httpd -y
sudo systemctl start httpd
sudo systemctl enable httpd
echo "<h1>Hello from Terraform!</h1>" > /var/www/html/index.html

  EOF

  tags = {
    Name        = "${var.project_name}-web-server"
    Environment = var.environment
  }

}

resource "aws_launch_configuration" "web" {
  name_prefix                 = "${var.project_name}-lc-"
  image_id                   = "ami-0c94855ba95c574c8" # Replace with your desired AMI
  instance_type              = "t2.micro"
  security_groups            = [aws_security_group.web_server_sg.id]
  user_data = <<-EOF
#!/bin/bash
sudo yum update -y
sudo yum install httpd -y
sudo systemctl start httpd
sudo systemctl enable httpd
echo "<h1>Hello from Terraform!</h1>" > /var/www/html/index.html

  EOF


  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "web" {
  name                      = "${var.project_name}-asg"
  vpc_zone_identifier       = [aws_subnet.public_1.id]
  min_size                  = 1
  max_size                  = 3
  health_check_grace_period = 300
  health_check_type         = "EC2"
  launch_configuration      = aws_launch_configuration.web.name

  tag {
    key                 = "Name"
    value               = "${var.project_name}-asg-instance"
    propagate_at_launch = true
  }

}


# RDS Instance
resource "aws_db_instance" "default" {
  allocated_storage          = 20
  storage_type              = "gp2"
  engine                     = "mysql"
  engine_version            = "8.0.28" # Replace with your desired version
  instance_class            = "db.t2.micro"
  name                      = "wordpressdb"
  username                  = var.db_username
  password                  = var.db_password
  parameter_group_name       = "default.mysql8.0" # Replace with your desired parameter group
  skip_final_snapshot       = true
  db_subnet_group_name      = aws_db_subnet_group.default.name
  vpc_security_group_ids     = [aws_security_group.rds_sg.id]
  storage_encrypted          = true
  backup_retention_period    = 7 # Set a reasonable backup retention period
  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]

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
  name                       = "${var.project_name}-lb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.web_server_sg.id]
  subnets                    = [aws_subnet.public_1.id]
  enable_deletion_protection = true
 drop_invalid_header_fields = true
  tags = {
    Name        = "${var.project_name}-lb"
    Environment = var.environment
  }
}

resource "aws_lb_target_group" "web" {
  name        = "${var.project_name}-lb-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"


  health_check {
    path                = "/"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 5
    timeout             = 5
  }

  tags = {
    Name        = "${var.project_name}-lb-tg"
    Environment = var.environment
  }
}

resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}


resource "aws_autoscaling_attachment" "asg_attachment_lb" {
  autoscaling_group_name = aws_autoscaling_group.web.name
  lb_target_group_arn    = aws_lb_target_group.web.arn
}


# S3 Bucket
resource "aws_s3_bucket" "static_assets" {
  bucket = "${var.project_name}-static-assets"
  acl    = "private"


  versioning {
    enabled = true
  }
  logging {
    target_bucket = "your-logging-bucket" # Replace with a dedicated logging bucket
    target_prefix = "log/"
  }

  tags = {
    Name        = "${var.project_name}-s3-bucket"
    Environment = var.environment
  }
}



# Cloudfront Distribution
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.static_assets.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.static_assets.id

    s3_origin_config {
      origin_access_identity = "origin-access-identity/cloudfront/ABCDEFG1234567" # Replace with your OAI
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_All"


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
    minimum_protocol_version = "TLSv1.2_2021"
  }

 tags = {
    Name        = "${var.project_name}-cloudfront"
    Environment = var.environment
  }


}




# Route53
resource "aws_route53_zone" "primary" {
  name = "example.com" # Replace with your domain name
 tags = {
    Name        = "${var.project_name}-route53"
    Environment = var.environment
  }
}


# Outputs
output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC"
}

output "rds_endpoint" {
  value       = aws_db_instance.default.endpoint
  description = "The endpoint of the RDS instance"
}

output "load_balancer_dns_name" {
  value       = aws_lb.web.dns_name
  description = "The DNS name of the load balancer"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.static_assets.bucket
  description = "The name of the S3 bucket"
}


