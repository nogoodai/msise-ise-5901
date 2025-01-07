# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Define variables for the configuration
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  default = ["us-west-2a", "us-west-2b"]
}

variable "instance_type" {
  default = "t2.micro"
}

variable "ami_id" {
  default = "ami-0c94855ba95c71c99"
}

variable "database_instance_class" {
  default = "db.t2.small"
}

variable "database_engine" {
  default = "mysql"
}

variable "elasticache_node_type" {
  default = "cache.t2.micro"
}

variable "elasticache_engine" {
  default = "memcached"
}

variable "cloudfront_origin_domain_name" {
  default = "example.com"
}

variable "route53_domain_name" {
  default = "example.com"
}

variable "wordpress_admin_username" {
  default = "admin"
}

variable "wordpress_admin_password" {
  default = "password"
}

variable "wordpress_database_username" {
  default = "wordpress"
}

variable "wordpress_database_password" {
  default = "password"
}

# Create a VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

# Create public subnets
resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PublicSubnet${count.index + 1}"
  }
}

# Create private subnets
resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PrivateSubnet${count.index + 1}"
  }
}

# Create an internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Create a public route table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicRouteTable"
  }
}

# Create a private route table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

# Create a route for the public route table
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Associate the public subnets with the public route table
resource "aws_route_table_association" "public_subnets_association" {
  count = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Associate the private subnets with the private route table
resource "aws_route_table_association" "private_subnets_association" {
  count = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Create a security group for the EC2 instances
resource "aws_security_group" "wordpress_ec2_sg" {
  name        = "WordPressEC2SG"
  description = "Security group for WordPress EC2 instances"
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
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "WordPressEC2SG"
  }
}

# Create a security group for the RDS instance
resource "aws_security_group" "wordpress_rds_sg" {
  name        = "WordPressRDSSG"
  description = "Security group for WordPress RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.wordpress_ec2_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "WordPressRDSSG"
  }
}

# Create a security group for the ELB
resource "aws_security_group" "wordpress_elb_sg" {
  name        = "WordPressELBSG"
  description = "Security group for WordPress ELB"
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
    Name = "WordPressELBSG"
  }
}

# Create an EC2 instance for WordPress
resource "aws_instance" "wordpress_ec2" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_ec2_sg.id]
  subnet_id = aws_subnet.public_subnets[0].id
  key_name = "wordpress"
  tags = {
    Name = "WordPressEC2"
  }
}

# Create an RDS instance for WordPress
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = var.database_engine
  engine_version       = "8.0.23"
  instance_class       = var.database_instance_class
  name                 = "wordpressdb"
  username             = var.wordpress_database_username
  password             = var.wordpress_database_password
  vpc_security_group_ids = [aws_security_group.wordpress_rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  tags = {
    Name = "WordPressRDS"
  }
}

# Create a DB subnet group for the RDS instance
resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = [aws_subnet.private_subnets[0].id, aws_subnet.private_subnets[1].id]
  tags = {
    Name = "WordPressRDSSubnetGroup"
  }
}

# Create an ELB for WordPress
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = [aws_subnet.public_subnets[0].id, aws_subnet.public_subnets[1].id]
  security_groups = [aws_security_group.wordpress_elb_sg.id]
  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
  listener {
    instance_port      = 443
    instance_protocol  = "https"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  }
  tags = {
    Name = "WordPressELB"
  }
}

# Create an Auto Scaling group for the EC2 instances
resource "aws_autoscaling_group" "wordpress_ec2_asg" {
  name                      = "wordpress-ec2-asg"
  max_size                  = 5
  min_size                  = 1
  vpc_zone_identifier       = [aws_subnet.public_subnets[0].id, aws_subnet.public_subnets[1].id]
  launch_configuration      = aws_launch_configuration.wordpress_ec2_lc.name
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  tag {
    key                 = "Name"
    value               = "WordPressEC2"
    propagate_at_launch = true
  }
}

# Create a launch configuration for the EC2 instances
resource "aws_launch_configuration" "wordpress_ec2_lc" {
  name          = "wordpress-ec2-lc"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.wordpress_ec2_sg.id]
  key_name = "wordpress"
  user_data = file("${path.module}/wordpress.sh")
  lifecycle {
    create_before_destroy = true
  }
}

# Create a CloudFront distribution for WordPress
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }
  enabled = true
  default_root_object = "index.html"
  aliases = [var.cloudfront_origin_domain_name]
  viewer_certificate {
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "sni-only"
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  tags = {
    Name = "WordPressCFD"
  }
}

# Create an S3 bucket for WordPress
resource "aws_s3_bucket" "wordpress_s3" {
  bucket = var.route53_domain_name
  acl    = "private"
  tags = {
    Name = "WordPressS3"
  }
}

# Create a Route 53 hosted zone for WordPress
resource "aws_route53_zone" "wordpress_r53" {
  name = var.route53_domain_name
  tags = {
    Name = "WordPressR53"
  }
}

# Create a Route 53 record for the ELB
resource "aws_route53_record" "wordpress_elb_r53" {
  zone_id = aws_route53_zone.wordpress_r53.zone_id
  name    = var.route53_domain_name
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

# Create a CloudWatch dashboard for WordPress
resource "aws_cloudwatch_dashboard" "wordpress_cwd" {
  dashboard_name = "WordPressCWD"
  dashboard_body = file("${path.module}/wordpress.json")
}
