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
  default = "dev"
}


# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project_name}-public-subnet-1"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "public_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  tags = {
    Name        = "${var.project_name}-public-subnet-2"
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

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

data "aws_availability_zones" "available" {}


# Security Groups

resource "aws_security_group" "web_server_sg" {
 name        = "${var.project_name}-web-server-sg"
  description = "Allow inbound traffic on ports 80, 443, and 22"
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

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Replace with your source IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-web-server-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}



# EC2 Instances & Autoscaling

resource "aws_launch_template" "wordpress_lt" {


  name_prefix   = "${var.project_name}-wordpress-lt-"
  image_id      = data.aws_ami.amazon_linux_2.id
 instance_type = "t3.micro"
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web_server_sg.id]
    subnet_id                   = aws_subnet.public_1.id
  }

  user_data = filebase64("${path.module}/user_data.sh") # Replace with your user data

 lifecycle {
    create_before_destroy = true
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


  name                      = "${var.project_name}-wordpress-asg"
  min_size                  = 2
  max_size                  = 4
  desired_capacity          = 2
  health_check_grace_period = 300
 health_check_type         = "ELB"
  launch_template {
    id      = aws_launch_template.wordpress_lt.id
    version = "$Latest"
  }


  vpc_zone_identifier = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  tag {
    key                 = "Name"
    value               = "${var.project_name}-wordpress-instance"
    propagate_at_launch = true
  }


}



# Load Balancer
resource "aws_lb" "wordpress_lb" {


  name               = "${var.project_name}-wordpress-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_server_sg.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]


  tags = {
    Name        = "${var.project_name}-wordpress-lb"
    Environment = var.environment
    Project     = var.project_name
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



resource "aws_lb_target_group" "wordpress_tg" {


  name        = "${var.project_name}-wordpress-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
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



resource "aws_autoscaling_attachment" "asg_attachment" {


  autoscaling_group_name = aws_autoscaling_group.wordpress_asg.name
  elb                    = aws_lb.wordpress_lb.arn


}


# S3 Bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "${var.project_name}-wordpress-bucket"
  acl    = "private"

  tags = {
    Name        = "${var.project_name}-wordpress-bucket"
    Environment = var.environment
    Project     = var.project_name
  }
}




# Route53 (Placeholder - Needs Domain Information)

# resource "aws_route53_record" "wordpress_record" {
#   zone_id = aws_route53_zone.main.zone_id  # Replace with your zone ID
#   name    = "wordpress.${aws_route53_zone.main.name}"
#   type    = "A"
#   alias {
#     name                   = aws_lb.wordpress_lb.dns_name
#     zone_id                = aws_lb.wordpress_lb.zone_id
#     evaluate_target_health = true
#   }
# }



output "lb_dns_name" {
  value = aws_lb.wordpress_lb.dns_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_bucket.bucket
}


