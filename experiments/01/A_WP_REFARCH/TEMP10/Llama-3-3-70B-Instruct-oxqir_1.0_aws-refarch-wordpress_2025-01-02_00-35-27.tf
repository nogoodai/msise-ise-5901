# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Define variables
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for EC2 instances"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c2ab3b8efb09f272"
  description = "ID of the AMI to use for EC2 instances"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Instance class for the RDS instance"
}

variable "database_username" {
  type        = string
  default     = "wordpress"
  description = "Username for the RDS database"
}

variable "database_password" {
  type        = string
  sensitive   = true
  default     = "password123"
  description = "Password for the RDS database"
}

# Create VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "wordpress-vpc"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create subnets
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-west-2a"
  map_public_ip_on_launch = true
  tags = {
    Name        = "public-subnet-1"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-west-2b"
  map_public_ip_on_launch = true
  tags = {
    Name        = "public-subnet-2"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name        = "private-subnet-1"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-west-2b"
  tags = {
    Name        = "private-subnet-2"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "wordpress-igw"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create route tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "public-route-table"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "private-route-table"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Associate route tables with subnets
resource "aws_route_table_association" "public_subnet_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnet_1" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_subnet_2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_route_table.id
}

# Create security groups
resource "aws_security_group" "wordpress_sg" {
  vpc_id      = aws_vpc.wordpress_vpc.id
  name        = "wordpress-sg"
  description = "Security group for WordPress instances"

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
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "wordpress-sg"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_security_group" "rds_sg" {
  vpc_id      = aws_vpc.wordpress_vpc.id
  name        = "rds-sg"
  description = "Security group for RDS instance"

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
  }

  tags = {
    Name        = "rds-sg"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_security_group" "elb_sg" {
  vpc_id      = aws_vpc.wordpress_vpc.id
  name        = "elb-sg"
  description = "Security group for ELB"

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
    Name        = "elb-sg"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create RDS instance
resource "aws_db_instance" "wordpress_rds" {
  instance_class         = var.rds_instance_class
  engine                 = "mysql"
  engine_version         = "8.0.23"
  parameter_group_name   = "default.mysql8.0"
  db_name                = "wordpress"
  username               = var.database_username
  password               = var.database_password
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  availability_zone      = "us-west-2a"
  backup_retention_period = 7
  skip_final_snapshot     = true
  tags = {
    Name        = "wordpress-rds"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create ELB
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  security_groups = [aws_security_group.elb_sg.id]

  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 80
    lb_protocol        = "http"
  }

  listener {
    instance_port      = 443
    instance_protocol  = "https"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "arn:aws:iam::123456789012:server-certificate/wordpress-ssl"
  }

  tags = {
    Name        = "wordpress-elb"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create EC2 instances
resource "aws_instance" "wordpress_instance" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  subnet_id     = aws_subnet.private_subnet_1.id
  key_name               = "wordpress-ssh"
  tags = {
    Name        = "wordpress-instance"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create Auto Scaling group
resource "aws_autoscaling_group" "wordpress_autoscaling_group" {
  name                      = "wordpress-autoscaling-group"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity         = 1
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_launch_configuration.name
  vpc_zone_identifier       = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
  tags = {
    Name        = "wordpress-autoscaling-group"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name          = "wordpress-launch-configuration"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.wordpress_sg.id]
  key_name               = "wordpress-ssh"
  user_data              = file("${path.module}/wordpress_user_data.sh")
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-elb"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name        = "wordpress-distribution"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create S3 bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-bucket"
  acl    = "private"

  tags = {
    Name        = "wordpress-bucket"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create Route 53 DNS record
resource "aws_route53_record" "wordpress_dns_record" {
  zone_id = "Z123456789012"
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

# Output ELB DNS name
output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

# Output CloudFront distribution domain name
output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_distribution.domain_name
}

# Output RDS instance endpoint
output "rds_instance_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}
