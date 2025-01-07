terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets."
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "administrative_access_ips" {
  description = "List of IPs allowed access to SSH."
  type        = list(string)
  default     = ["203.0.113.0/24"]
}

variable "tags" {
  description = "Tags to apply to resources."
  type        = map(string)
  default     = {
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = merge(var.tags, { Name = "wordpress-vpc" })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags   = merge(var.tags, { Name = "igw" })
}

resource "aws_subnet" "public" {
  for_each = toset(var.public_subnet_cidrs)
  
  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = each.value
  map_public_ip_on_launch = true
  availability_zone = element(data.aws_availability_zones.available.names, index(var.public_subnet_cidrs, each.value))

  tags = merge(var.tags, { Name = "public-subnet-${index(var.public_subnet_cidrs, each.value)}" })
}

resource "aws_subnet" "private" {
  for_each = toset(var.private_subnet_cidrs)

  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = each.value
  availability_zone = element(data.aws_availability_zones.available.names, index(var.private_subnet_cidrs, each.value))

  tags = merge(var.tags, { Name = "private-subnet-${index(var.private_subnet_cidrs, each.value)}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(var.tags, { Name = "public-route-table" })
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id

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
    cidr_blocks = var.administrative_access_ips
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "web-sg" })
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "db-sg" })
}

resource "aws_instance" "bastion_host" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  key_name      = aws_key_pair.ssh_key.key_name

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  associate_public_ip_address = true

  tags = merge(var.tags, { Name = "bastion-host" })
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["137112412989"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_key_pair" "ssh_key" {
  key_name   = "bastion-key"
  public_key = file(var.ssh_public_key_path)

  tags = merge(var.tags, { Name = "bastion-key" })
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

resource "aws_elastic_ip" "bastion_eip" {
  depends_on = [aws_instance.bastion_host]

  instance = aws_instance.bastion_host.id
  tags     = merge(var.tags, { Name = "bastion-eip" })
}

resource "aws_efs_file_system" "wordpress_efs" {
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  performance_mode = "generalPurpose"

  tags = merge(var.tags, { Name = "wordpress-efs" })
}

resource "aws_efs_mount_target" "wordpress_mount_target" {
  for_each = aws_subnet.private

  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = each.value.id
  security_groups = [aws_security_group.web_sg.id]

  tags = merge(var.tags, { Name = "wordpress-mount-target" })
}

resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  max_allocated_storage = 100
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  multi_az             = true
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t2.small"
  name                 = "wordpressdb"
  username             = "admin"
  password             = random_password.db_password.result
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  
  tags = merge(var.tags, { Name = "wordpress-db" })
}

resource "random_password" "db_password" {
  length  = 16
  special = true
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = merge(var.tags, { Name = "wordpress-db-subnet-group" })
}

resource "aws_elb" "wordpress_elb" {
  name               = "wordpress-elb"
  availability_zones = data.aws_availability_zones.available.names

  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    target              = "HTTP:80/"
    interval            = 30
  }

  security_groups = [aws_security_group.web_sg.id]
  subnets         = aws_subnet.public[*].id

  tags = merge(var.tags, { Name = "wordpress-elb" })
}

resource "aws_autoscaling_group" "wordpress_asg" {
  launch_configuration = aws_launch_configuration.wordpress_launch_config.id
  min_size             = 2
  max_size             = 5
  vpc_zone_identifier  = aws_subnet.public[*].id

  target_group_arns = [aws_lb_target_group.wordpress_target_group.arn]

  tags = [
    {
      key                 = "Name"
      value               = "wordpress-asg"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = var.tags["Environment"]
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_launch_config" {
  image_id               = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  associate_public_ip_address = true
  user_data              = file("user_data.sh")

  security_groups = [aws_security_group.web_sg.id]

  iam_instance_profile = aws_iam_instance_profile.wordpress_instance_profile.id

  key_name = aws_key_pair.ssh_key.key_name

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_instance_profile" "wordpress_instance_profile" {
  name = "wordpress-instance-profile"

  roles = [aws_iam_role.wordpress_role.name]
}

resource "aws_iam_role" "wordpress_role" {
  name = "wordpress-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = merge(var.tags, { Name = "wordpress-role" })
}

resource "aws_iam_role_policy_attachment" "wordpress_access" {
  role       = aws_iam_role.wordpress_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-bucket"

  tags = merge(var.tags, { Name = "wordpress-assets" })
}

resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "wordpressS3"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.wordpress_identity.cloudfront_access_identity_path
    }
  }

  enabled = true

  default_cache_behavior {
    target_origin_id = "wordpressS3"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  tags = var.tags
}

resource "aws_cloudfront_origin_access_identity" "wordpress_identity" {
  comment = "Access S3 bucket only through CloudFront"
}

resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
}

variable "domain_name" {
  description = "The domain name for WordPress."
  type        = string
  default     = "example.com"
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "db_instance_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cdn.domain_name
}
