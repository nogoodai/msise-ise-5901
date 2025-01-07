# Define the Terraform provider and version
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
  required_version = ">= 1.3.0"
}

# Configure the AWS provider
provider "aws" {
  region = "us-west-2"
}

# Define variables for the configuration
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}

variable "aws_availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "The availability zones for the subnets"
}

variable "db_instance_username" {
  type        = string
  default     = "wordpress"
  sensitive   = true
  description = "The username for the RDS instance"
}

variable "db_instance_password" {
  type        = string
  sensitive   = true
  description = "The password for the RDS instance"
}

variable "web_server_security_group_ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "The CIDR blocks for ingress to the web server security group"
}

variable "web_server_security_group_ingress_ports" {
  type        = list(number)
  default     = [22, 80, 443]
  description = "The ports for ingress to the web server security group"
}

variable "ssh_key_pair_name" {
  type        = string
  default     = "wordpress-ssh-key"
  description = "The name of the SSH key pair"
}

variable "wordpress_db_name" {
  type        = string
  default     = "wordpressdb"
  description = "The name of the WordPress database"
}

variable "wordpress_db_username" {
  type        = string
  default     = "wordpress"
  sensitive   = true
  description = "The username for the WordPress database"
}

variable "wordpress_db_password" {
  type        = string
  sensitive   = true
  description = "The password for the WordPress database"
}

# Create the VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "WordPressVPC"
  }
}

# Create the subnets
resource "aws_subnet" "wordpress_subnets" {
  count             = 3
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 8, count.index)
  availability_zone = var.aws_availability_zones[count.index]
  tags = {
    Name = "WordPressSubnet${count.index}"
  }
}

# Create the internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Create the route tables
resource "aws_route_table" "wordpress_route_table" {
  count = 2
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressRouteTable${count.index}"
  }
}

# Create the routes
resource "aws_route" "wordpress_igw_route" {
  route_table_id         = aws_route_table.wordpress_route_table[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Associate the subnets with the route tables
resource "aws_route_table_association" "wordpress_subnets_association" {
  count          = 3
  subnet_id      = aws_subnet.wordpress_subnets[count.index].id
  route_table_id = aws_route_table.wordpress_route_table[count.index % 2].id
}

# Create the security groups
resource "aws_security_group" "wordpress_sg" {
  name        = "WordPressSG"
  description = "Security group for the WordPress instances"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.web_server_security_group_ingress_cidr_blocks
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.web_server_security_group_ingress_cidr_blocks
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.web_server_security_group_ingress_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WordPressSG"
  }
}

resource "aws_security_group" "wordpress_db_sg" {
  name        = "WordPressDBSG"
  description = "Security group for the WordPress database"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
  }

  tags = {
    Name = "WordPressDBSG"
  }
}

# Create the RDS instance
resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = "db.t2.micro"
  db_name              = var.wordpress_db_name
  username             = var.wordpress_db_username
  password             = var.wordpress_db_password
  parameter_group_name = "default.mysql8.0"
  vpc_security_group_ids = [aws_security_group.wordpress_db_sg.id]
  tags = {
    Name = "WordPressDB"
  }
}

# Create the EC2 instances for WordPress
resource "aws_instance" "wordpress_servers" {
  count         = 3
  ami           = "ami-0c2ab3b8efb09f272"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  subnet_id = aws_subnet.wordpress_subnets[count.index].id
  tags = {
    Name = "WordPressServer${count.index}"
  }
}

# Create the Auto Scaling Group for the EC2 instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  max_size                  = 3
  min_size                  = 1
  vpc_zone_identifier       = aws_subnet.wordpress_subnets[0].id
  launch_template {
    id      = aws_launch_template.wordpress_template.id
    version = "$Latest"
  }
}

# Create the launch template for the EC2 instances
resource "aws_launch_template" "wordpress_template" {
  name          = "WordPressTemplate"
  image_id      = "ami-0c2ab3b8efb09f272"
  instance_type = "t2.micro"
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.wordpress_sg.id]
  }
  user_data = base64encode(file("${path.module}/wordpress.sh"))
}

# Create the Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = aws_subnet.wordpress_subnets[*].id
  security_groups = [aws_security_group.wordpress_sg.id]

  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
}

# Create the CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.wordpress_bucket.id
  }

  aliases = ["example.com"]
}

# Create the S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "example-wordpress-bucket"
  acl    = "private"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Name = "WordPressBucket"
  }
}

# Create the Route 53 DNS configuration
resource "aws_route53_zone" "example_com" {
  name = "example.com"
}

resource "aws_route53_record" "example_com" {
  zone_id = aws_route53_zone.example_com.id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "s3_bucket_id" {
  value = aws_s3_bucket.wordpress_bucket.id
}

output "route53_zone_id" {
  value = aws_route53_zone.example_com.id
}
