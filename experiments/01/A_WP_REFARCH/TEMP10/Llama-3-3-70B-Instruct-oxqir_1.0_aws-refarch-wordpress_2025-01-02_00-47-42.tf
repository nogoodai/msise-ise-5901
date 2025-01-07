# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Define variables for the VPC and networking resources
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "A list of Availability Zones"
}

# Create a VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
  }
}

# Create subnets
resource "aws_subnet" "public_subnet" {
  count             = length(var.availability_zones)
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  vpc_id            = aws_vpc.wordpress_vpc.id
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PublicSubnet-${count.index + 1}"
    Environment = "production"
  }
}

resource "aws_subnet" "private_subnet" {
  count             = length(var.availability_zones)
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, length(var.availability_zones) + count.index)
  vpc_id            = aws_vpc.wordpress_vpc.id
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PrivateSubnet-${count.index + 1}"
    Environment = "production"
  }
}

# Create an Internet Gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
  }
}

# Create route tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = "production"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = "production"
  }
}

# Associate route tables with subnets
resource "aws_route_table_association" "public_subnet_association" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnet_association" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Add a route to the Internet Gateway
resource "aws_route" "igw_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Define security groups
resource "aws_security_group" "web_server_sg" {
  name        = "WordPressWebServerSG"
  description = "Allow inbound HTTP and HTTPS traffic"
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
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "WordPressWebServerSG"
    Environment = "production"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "WordPressRDSSG"
  description = "Allow inbound MySQL traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "WordPressRDSSG"
    Environment = "production"
  }
}

# Create an RDS instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = "db.t2.micro"
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  skip_final_snapshot  = true
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress_db_subnet_group"
  subnet_ids = [aws_subnet.private_subnet[0].id, aws_subnet.private_subnet[1].id, aws_subnet.private_subnet[2].id]
  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = "production"
  }
}

# Create an Elastic Load Balancer
resource "aws_alb" "wordpress_alb" {
  name            = "WordPressALB"
  subnets         = [aws_subnet.public_subnet[0].id, aws_subnet.public_subnet[1].id, aws_subnet.public_subnet[2].id]
  security_groups = [aws_security_group.web_server_sg.id]
  tags = {
    Name        = "WordPressALB"
    Environment = "production"
  }
}

# Create a target group
resource "aws_alb_target_group" "wordpress_target_group" {
  name     = "WordPressTargetGroup"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  health_check {
    healthy_threshold   = 5
    unhealthy_threshold = 10
    timeout             = 5
    path                = "/"
    interval            = 10
  }
  tags = {
    Name        = "WordPressTargetGroup"
    Environment = "production"
  }
}

# Create an Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "WordPressASG"
  max_size            = 5
  min_size            = 1
  vpc_zone_identifier = [aws_subnet.private_subnet[0].id, aws_subnet.private_subnet[1].id, aws_subnet.private_subnet[2].id]
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  target_group_arns   = [aws_alb_target_group.wordpress_target_group.arn]
  tags = [
    {
      key                 = "Name"
      value               = "WordPressEC2"
      propagate_at_launch = true
    },
  ]
}

# Create a launch configuration
resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  security_groups = [
    aws_security_group.web_server_sg.id,
  ]
  user_data = file("${path.module}/user_data.sh")
  lifecycle {
    create_before_destroy = true
  }
}

# Create an S3 bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket        = "wordpress-bucket"
  force_destroy = true
  tags = {
    Name        = "WordPressBucket"
    Environment = "production"
  }
}

# Create a CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = "WordPressOrigin"
  }
  enabled         = true
  default_root_object = "index.html"
  aliases = ["example.com"]
  custom_error_response {
    error_caching_min_ttl = 0
    error_code            = 404
    response_code         = 200
    response_page_path    = "/404.html"
  }
  viewer_certificate {
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "sni-only"
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  tags = {
    Name        = "WordPressDistribution"
    Environment = "production"
  }
}

# Create a Route 53 record
resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "example.com"
  type    = "A"
  alias {
    name                   = aws_alb.wordpress_alb.dns_name
    zone_id               = aws_alb.wordpress_alb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
}

# Output the CloudFront distribution URL
output "cloudfront_distribution_url" {
  value = aws_cloudfront_distribution.wordpress_distribution.domain_name
}
