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
  tags        = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags              = {
    Name        = "${var.project_name}-public-subnet-1"
    Environment = var.environment
  }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags              = {
    Name        = "${var.project_name}-private-subnet-1"
    Environment = var.environment
  }
}


data "aws_availability_zones" "available" {}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags   = {
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

resource "aws_security_group" "web_sg" {
 name        = "${var.project_name}-web-sg"
 description = "Allow inbound HTTP and HTTPS"
 vpc_id      = aws_vpc.main.id

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
   Name        = "${var.project_name}-web-sg"
   Environment = var.environment
 }
}


resource "aws_security_group" "rds_sg" {
 name        = "${var.project_name}-rds-sg"
 description = "Allow inbound traffic from web servers"
 vpc_id      = aws_vpc.main.id

 ingress {
   from_port        = 3306
   to_port          = 3306
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
   Name        = "${var.project_name}-rds-sg"
   Environment = var.environment
 }
}


# EC2 Instances (using an ASG)

resource "aws_launch_configuration" "wordpress_lc" {
 image_id            = "ami-0c94855ba95c574c7" # Replace with desired AMI
 instance_type        = "t2.micro"
 security_groups      = [aws_security_group.web_sg.id]
 key_name             = "your-key-name" # Replace with your key name
 user_data            = file("user_data.sh") # Create a user_data.sh file for WordPress installation


 lifecycle {
   create_before_destroy = true
 }

}


resource "aws_autoscaling_group" "wordpress_asg" {
 name                 = "${var.project_name}-wordpress-asg"
 launch_configuration = aws_launch_configuration.wordpress_lc.name
 min_size             = 2
 max_size             = 4
 vpc_zone_identifier  = [aws_subnet.public_1.id]
 health_check_type   = "ELB"
 health_check_grace_period = 300
 tags = [
   {
     key                 = "Name"
     value               = "${var.project_name}-wordpress-instance"
     propagate_at_launch = true
   },
   {
     key                 = "Environment"
     value               = var.environment
     propagate_at_launch = true
   },
 ]
}

# RDS Instance

resource "aws_db_instance" "wordpress_db" {
   identifier             = "${var.project_name}-wordpress-db"
 allocated_storage    = 20
 db_name              = "wordpress"
 engine               = "mysql"
 engine_version        = "8.0" # Or your preferred version
 instance_class        = "db.t2.micro"
 username             = "wordpressuser" # Replace with your preferred username.
 password             = "password123" # Replace with a secure password.
   vpc_security_group_ids = [aws_security_group.rds_sg.id]
   skip_final_snapshot   = true
   db_subnet_group_name  = aws_db_subnet_group.default.name
   tags = {
     Name        = "${var.project_name}-rds-instance"
     Environment = var.environment

 }
}


resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_1.id]

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}





# Elastic Load Balancer


resource "aws_elb" "wordpress_elb" {

 name            = "${var.project_name}-elb"
 security_groups = [aws_security_group.web_sg.id]
 subnets         = [aws_subnet.public_1.id]


 listener {
 instance_port      = 80
 instance_protocol  = "http"
 lb_port             = 80
 lb_protocol         = "http"
 }

 health_check {
 healthy_threshold   = 2
 unhealthy_threshold = 2
 timeout             = 5
 target              = "HTTP:80/"
 interval            = 30
 }


 tags = {

   Name        = "${var.project_name}-elb"
   Environment = var.environment

 }


}

resource "aws_elb_attachment" "wordpress_elb_attachment" {
  elbs              = [aws_elb.wordpress_elb.id]
  instances         = aws_autoscaling_group.wordpress_asg.instances
}

# S3 Bucket for Static Assets


resource "aws_s3_bucket" "wordpress_s3_bucket" {
 bucket = "${var.project_name}-wordpress-assets"
 acl    = "private"
 tags = {
   Name = "${var.project_name}-s3-bucket"
 }
}



# Cloudfront (simplified example - adjust as needed)

resource "aws_cloudfront_distribution" "s3_distribution" {
 origin {
   domain_name = aws_s3_bucket.wordpress_s3_bucket.bucket_regional_domain_name
   origin_id   = aws_s3_bucket.wordpress_s3_bucket.bucket
 }

 enabled             = true
 is_ipv6_enabled     = true
 default_root_object = "index.html"
 price_class        = "PriceClass_All" # Adjust as needed
 viewer_certificate {
   cloudfront_default_certificate = true
 }

 default_cache_behavior {
   allowed_methods  = ["GET", "HEAD"]
   cached_methods   = ["GET", "HEAD"]
   target_origin_id = aws_s3_bucket.wordpress_s3_bucket.bucket
   viewer_protocol_policy = "redirect-to-https" # Or allow-all, https-only
 }
 restrictions {
  geo_restriction {
    restriction_type = "none"
  }
 }
}

# Route53 (replace with your domain)

# resource "aws_route53_record" "wordpress_record" {
#   zone_id = "YOUR_ZONE_ID" # Replace with your zone ID
#   name    = "www.example.com" # Replace with your domain
#   type    = "A"


#   alias {
#     name                   = aws_elb.wordpress_elb.dns_name
#     zone_id                = aws_elb.wordpress_elb.zone_id
#     evaluate_target_health = true
#   }
# }


output "elb_dns_name" {
 value = aws_elb.wordpress_elb.dns_name
}

output "s3_bucket_name" {
 value = aws_s3_bucket.wordpress_s3_bucket.id
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.s3_distribution.domain_name
}


