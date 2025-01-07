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

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}



# VPC and Networking
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "wordpress-vpc"
    Environment = "production"
  }
}

resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "wordpress-public-subnet-${count.index}"
    Environment = "production"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "wordpress-private-subnet-${count.index}"
    Environment = "production"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "wordpress-igw"
    Environment = "production"
  }
}


resource "aws_route_table" "public_route_table" {
 vpc_id = aws_vpc.wordpress_vpc.id
 route {
   cidr_block = "0.0.0.0/0"
   gateway_id = aws_internet_gateway.wordpress_igw.id
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



# Security Groups

resource "aws_security_group" "wordpress_sg" {
  name        = "wordpress-sg"
  description = "Allow inbound HTTP, HTTPS and SSH"
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
    Name = "allow_tls"
  }
}



resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Allow inbound traffic from web servers"
  vpc_id      = aws_vpc.wordpress_vpc.id

 ingress {
   from_port        = 3306
   to_port          = 3306
   protocol         = "tcp"
   security_groups = [aws_security_group.wordpress_sg.id]
 }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# EC2 Instances and Autoscaling
resource "aws_instance" "wordpress_instances" {
  count         = 2
  ami           = data.aws_ami.amazon_linux_2.id # Replace with desired AMI
  instance_type = var.instance_type
  subnet_id = element(aws_subnet.public_subnets.*.id, count.index) # Distribute instances across AZs
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]

  user_data = <<EOF
#!/bin/bash
yum update -y
yum install httpd php mysql php-mysql -y
systemctl start httpd
systemctl enable httpd
echo "<h1>Hello from instance #${count.index}</h1>" > /var/www/html/index.html

EOF

  tags = {
    Name        = "wordpress-instance-${count.index}"
    Environment = "production"
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


resource "aws_elb" "wordpress_elb" {
  name               = "wordpress-elb"
  subnets            = aws_subnet.public_subnets.*.id
  security_groups    = [aws_security_group.wordpress_sg.id]
  internal           = false
  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port          = 80
    lb_protocol      = "http"
  }


 health_check {
   healthy_threshold   = 2
   unhealthy_threshold = 2
   timeout             = 3
   target              = "HTTP:80/"
   interval            = 30
 }


  tags = {
    Name        = "wordpress-elb"
    Environment = "production"

  }
}


resource "aws_elb_attachment" "wordpress_elb_attachment" {
  count            = length(aws_instance.wordpress_instances)
  elb              = aws_elb.wordpress_elb.id
  instance         = aws_instance.wordpress_instances[count.index].id
}





# RDS Instance
resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "8.0" # Replace with desired version
  instance_class       = var.db_instance_class
  name                = "wordpressdb"
  username             = "admin" # Replace with your username
  password             = "password123"
  skip_final_snapshot = true
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
 vpc_security_group_ids = [aws_security_group.rds_sg.id]
  tags = {
    Name        = "wordpress-db"
    Environment = "production"
  }
}


resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "main"
  subnet_ids = aws_subnet.private_subnets.*.id
  tags = {
    Name = "My db subnet group"
  }
}




# Output
output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "rds_endpoint" {
 value = aws_db_instance.wordpress_db.endpoint
}
