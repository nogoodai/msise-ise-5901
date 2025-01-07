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

variable "availability_zones" {
  type    = list(string)
  default = ["us-west-2a", "us-west-2b"]
}


resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name = "wordpress-igw"
  }
}


resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "wordpress-public-subnet-${count.index}"
  }

}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "wordpress-private-subnet-${count.index}"
  }
}



resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "wordpress-public-route-table"
  }
}


resource "aws_route_table_association" "public_subnet_association" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table" "private_route_table" {
 vpc_id = aws_vpc.wordpress_vpc.id
 tags = {
    Name = "wordpress-private-route-table"
  }
}


resource "aws_route_table_association" "private_subnet_association" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}


resource "aws_security_group" "web_sg" {
  name        = "wordpress-web-sg"
  description = "Allow inbound HTTP and HTTPS"
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
    cidr_blocks = ["0.0.0.0/0"] # Replace with your IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress-web-sg"
  }
}




resource "aws_instance" "wordpress_instances" {
  count = 2
  ami           = "ami-0c94855ba95c574c8" # Replace with your desired AMI
  instance_type = "t2.micro"
  subnet_id = aws_subnet.private_subnets[count.index].id

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = <<-EOF
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
    Name = "wordpress-instance-${count.index}"
  }
}


resource "aws_db_instance" "wordpress_db" {

  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t2.micro"
  username             = "admin" # Replace with your desired username
  password             = "password123" # Replace with a strong password
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true

  db_subnet_group_name = aws_db_subnet_group.default.name


    vpc_security_group_ids = [aws_security_group.rds_sg.id]



  tags = {
    Name = "wordpress-db"
  }

}


resource "aws_security_group" "rds_sg" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"
  vpc_id = aws_vpc.wordpress_vpc.id



 ingress {
 from_port = 3306
 to_port = 3306
 protocol = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }




}

resource "aws_db_subnet_group" "default" {
 name       = "main"
 subnet_ids = aws_subnet.private_subnets[*].id

  tags = {
    Name = "My db subnet group"
  }
}

output "db_endpoint" {
  value = aws_db_instance.wordpress_db.address
}

output "db_port" {
  value = aws_db_instance.wordpress_db.port
}


resource "aws_lb" "wordpress_lb" {
  name               = "wordpress-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets = aws_subnet.public_subnets[*].id


}


resource "aws_security_group" "lb_sg" {
  name        = "allow_http"
  description = "Allow HTTP inbound traffic"
 vpc_id = aws_vpc.wordpress_vpc.id

  ingress {
 from_port = 80
 to_port = 80
 protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
 from_port = 443
 to_port = 443
 protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_lb_target_group" "wordpress_tg" {
  name        = "wordpress-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.wordpress_vpc.id


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



resource "aws_lb_listener" "http" {

  load_balancer_arn = aws_lb.wordpress_lb.arn
  port              = "80"
  protocol          = "HTTP"


  default_action {
    type             = "forward"
 target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }

}



resource "aws_lb_listener" "https" {
 load_balancer_arn = aws_lb.wordpress_lb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08" # Update with your desired SSL policy



  default_action {
    type             = "forward"
 target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}




resource "aws_lb_target_group_attachment" "wordpress_tg_attachment" {
  count            = length(aws_instance.wordpress_instances)
 target_group_arn = aws_lb_target_group.wordpress_tg.arn
  target_id        = aws_instance.wordpress_instances[count.index].id
  port             = 80
}



output "lb_dns_name" {
 value = aws_lb.wordpress_lb.dns_name
}



resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${random_id.bucket_id.hex}"
  acl    = "private"


}



resource "random_id" "bucket_id" {
  byte_length = 8
}

resource "aws_cloudfront_distribution" "wordpress_cdn" {
 origin {
    domain_name = aws_lb.wordpress_lb.dns_name
 origin_id   = "wordpress-lb-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # Or "https-only" if you have SSL configured on your origin
      origin_ssl_protocols   = ["TLSv1.2"]

    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "WordPress CDN"
 default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
 target_origin_id = "wordpress-lb-origin"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
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



output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cdn.domain_name
}



resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com" # Replace with your domain name
}

resource "aws_route53_record" "cloudfront_alias" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "cdn.example.com" # Replace with your desired subdomain
  type    = "A"
 alias {
 name = aws_cloudfront_distribution.wordpress_cdn.domain_name
    zone_id = aws_cloudfront_distribution.wordpress_cdn.hosted_zone_id
    evaluate_target_health = false

  }


}


resource "aws_autoscaling_group" "wordpress_asg" {
 name                 = "wordpress-asg"
  min_size             = 2
  max_size             = 4
  vpc_zone_identifier  = aws_subnet.private_subnets[*].id


  health_check_grace_period = 300
  health_check_type         = "ELB"
  target_group_arns         = [aws_lb_target_group.wordpress_tg.arn]

  launch_template {
 id      = aws_launch_template.wordpress_lt.id
    version = "$Latest"
  }

}

resource "aws_launch_template" "wordpress_lt" {

  name_prefix   = "wordpress-lt-"
  instance_type = "t2.micro"

  network_interfaces {


 security_groups = [aws_security_group.web_sg.id]
  }



  image_id = "ami-0c94855ba95c574c8" # Replace with your desired AMI
 user_data = base64encode(<<-EOF
#!/bin/bash
sudo yum update -y
sudo amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2
sudo yum install -y httpd mariadb-server
sudo systemctl start httpd
sudo systemctl enable httpd
sudo systemctl start mariadb
sudo systemctl enable mariadb
  EOF
)
}



