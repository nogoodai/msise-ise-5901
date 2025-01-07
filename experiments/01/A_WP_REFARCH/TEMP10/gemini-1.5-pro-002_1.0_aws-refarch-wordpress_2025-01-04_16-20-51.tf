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

resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name        = "${var.project_name}-public-subnet-a"
    Environment = var.environment
    Project     = var.project_name
  }

}

resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  tags = {
    Name        = "${var.project_name}-public-subnet-b"
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

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}


data "aws_availability_zones" "available" {}
# Security Groups

resource "aws_security_group" "web_server_sg" {
  name        = "${var.project_name}-web-server-sg"
  description = "Allow inbound HTTP and HTTPS access"
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
    cidr_blocks = ["0.0.0.0/0"] # Replace with your IP
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

resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow inbound access from web servers"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
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
    Project     = var.project_name
  }
}



# EC2 Instances


resource "aws_instance" "web_server" {
  ami           = "ami-0c94855ba95c574c8" # Replace with your desired AMI
  instance_type = "t2.micro"
  subnet_id              = aws_subnet.public_a.id

  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  user_data = file("user_data.sh") # Replace with your user data script

  tags = {
    Name        = "${var.project_name}-web-server"
    Environment = var.environment
    Project     = var.project_name
  }
}



# RDS Instance

resource "aws_db_instance" "default" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t2.micro"
  name                 = "wordpress"
  username             = "admin" # Replace with your username
  password             = "password"  # Replace with your password. Use random provider
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.default.name

  tags = {
    Name        = "${var.project_name}-rds"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
    Project     = var.project_name
  }

}



# Elastic Load Balancer
resource "aws_lb" "alb" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_server_sg.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]


  tags = {
    Name        = "${var.project_name}-alb"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"


  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}


resource "aws_lb_target_group" "main" {
  name        = "${var.project_name}-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"



  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }


}

resource "aws_lb_target_group_attachment" "main" {
  target_group_arn = aws_lb_target_group.main.arn
  target_id        = aws_instance.web_server.id
  port             = 80
}





# Autoscaling Group



resource "aws_autoscaling_group" "web_server_asg" {
  name                 = "${var.project_name}-web-server-asg"

  min_size             = 1
  max_size             = 3
  vpc_zone_identifier  = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  health_check_grace_period = 300
  health_check_type         = "ELB"
  default_cooldown         = 300
  force_delete            = true
  target_group_arns       = [aws_lb_target_group.main.arn]


  launch_template {
    id      = aws_launch_template.web_server_lt.id
    version = "$Latest"
  }


  tag {
    key                 = "Name"
    value               = "${var.project_name}-web-server-instance"
    propagate_at_launch = true
  }

}


resource "aws_launch_template" "web_server_lt" {
  name_prefix   = "${var.project_name}-web-server-lt-"


  instance_market_options {
    market_type = "spot"

    spot_options {

      block_duration_minutes = 60
      instance_interruption_behavior = "terminate"
      max_price = "0.05" # Adjust the max price accordingly
      spot_instance_type = "one-time" # Choose one-time, or persistent spot instances as needed
      valid_until = "2024-07-27T15:03:00Z"
    }

  }


  image_id      = "ami-0c94855ba95c574c8" # Replace with your desired AMI
  instance_type = "t2.micro"



  network_interfaces {
    associate_public_ip_address = true
    delete_on_termination       = true
    security_groups             = [aws_security_group.web_server_sg.id]

  }


  tag_specifications {
    resource_type = "instance"

    tag {
      key                 = "Name"
      value               = "${var.project_name}-web-server-instance"
      propagate_at_launch = true
    }
  }


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
    Project     = var.project_name
  }
}





output "alb_dns_name" {
  value = aws_lb.alb.dns_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.static_assets.bucket
}


