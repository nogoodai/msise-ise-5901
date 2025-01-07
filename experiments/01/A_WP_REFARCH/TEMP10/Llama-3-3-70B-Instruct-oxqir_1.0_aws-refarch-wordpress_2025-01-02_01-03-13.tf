# Configure the AWS provider
provider "aws" {
  region = "us-west-2"
}

# Define variables for the configuration
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
}

variable "db_instance_class" {
  type        = string
  default     = "db.t2.small"
}

variable "bastion_instance_type" {
  type        = string
  default     = "t2.micro"
}

variable "ws_ami_id" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
}

variable "cache_node_type" {
  type        = string
  default     = "cache.t2.micro"
}

variable "db_engine" {
  type        = string
  default     = "mysql"
}

variable "cache_engine" {
  type        = string
  default     = "memcached"
}

# Create a VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

# Create public and private subnets
resource "aws_subnet" "public_subnets" {
  count = length(var.availability_zones)
  vpc_id   = aws_vpc.wordpress_vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "PublicSubnet-${count.index}"
  }
}

resource "aws_subnet" "private_subnets" {
  count = length(var.availability_zones)
  vpc_id   = aws_vpc.wordpress_vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index + 16)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PrivateSubnet-${count.index}"
  }
}

# Create an internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Create public and private route tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

# Create routes for the public route table
resource "aws_route" "public_route" {
  route_table_id            = aws_route_table.public_route_table.id
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id                = aws_internet_gateway.wordpress_igw.id
}

# Associate the public subnets with the public route table
resource "aws_route_table_association" "public_subnets" {
  count = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Associate the private subnets with the private route table
resource "aws_route_table_association" "private_subnets" {
  count = length(var.availability_zones)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Create security groups
resource "aws_security_group" "web_server_sg" {
  name        = "WordPressWebServerSG"
  description = "Web server security group"
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
    Name = "WordPressWebServerSG"
  }
}

resource "aws_security_group" "db_sg" {
  name        = "WordPressDBSG"
  description = "DB security group"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    security_groups = [aws_security_group.web_server_sg.id]
  }

  tags = {
    Name = "WordPressDBSG"
  }
}

resource "aws_security_group" "elb_sg" {
  name        = "WordPressELBSG"
  description = "ELB security group"
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

# Create an Elastic File System (EFS)
resource "aws_efs_file_system" "wordpress_efs" {
  creation_token = "wordpress-efs"
  tags = {
    Name = "WordPressEFS"
  }
}

# Create mount targets for the EFS
resource "aws_efs_mount_target" "wordpress_efs_mount_targets" {
  count = length(var.availability_zones)
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id = aws_subnet.private_subnets[count.index].id
  security_groups = [aws_security_group.web_server_sg.id]
}

# Create an RDS instance
resource "aws_db_instance" "wordpress_db" {
  identifier        = "wordpress-db"
  engine            = var.db_engine
  instance_class    = var.db_instance_class
  allocated_storage = 20
  username          = "adminuser"
  password          = "adminpassword"
  skip_final_snapshot = true
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  tags = {
    Name = "WordPressDB"
  }
}

# Create a DB subnet group
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name        = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private_subnets.*.id
  tags = {
    Name = "WordPressDBSubnetGroup"
  }
}

# Create an Elasticache cluster
resource "aws_elasticache_cluster" "wordpress_cache" {
  cluster_id           = "wordpress-cache"
  engine               = var.cache_engine
  node_type            = var.cache_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis5.0"
  port                 = 6379
  tags = {
    Name = "WordPressCache"
  }
}

# Create an Elasticache subnet group
resource "aws_elasticache_subnet_group" "wordpress_cache_subnet_group" {
  name        = "wordpress-cache-subnet-group"
  subnet_ids = aws_subnet.private_subnets.*.id
  tags = {
    Name = "WordPressCacheSubnetGroup"
  }
}

# Create an Application Load Balancer (ALB)
resource "aws_lb" "wordpress_alb" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.elb_sg.id]
  subnets            = aws_subnet.public_subnets.*.id
  tags = {
    Name = "WordPressALB"
  }
}

# Create a target group
resource "aws_lb_target_group" "wordpress_alb_target_group" {
  name     = "wordpress-alb-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressALBTargetGroup"
  }
}

# Create a listener
resource "aws_lb_listener" "wordpress_alb_listener" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_alb_target_group.arn
  }
}

# Create a CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cloudfront_distribution" {
  enabled = true

  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = "wordpress-alb"
  }

  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-alb"

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

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "WordPressCloudFrontDistribution"
  }
}

# Create an S3 bucket
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = "wordpress-bucket"
  acl    = "private"

  tags = {
    Name = "WordPressS3Bucket"
  }
}

# Create a Route 53 DNS record
resource "aws_route53_record" "wordpress_dns_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cloudfront_distribution.zone_id
    evaluate_target_health = true
  }
}

# Create a Route 53 hosted zone
resource "aws_route53_zone" "wordpress_zone" {
  name    = "example.com"
  comment = "Route 53 hosted zone"

  tags = {
    Name = "WordPressRoute53Zone"
  }
}

# Create an EC2 instance for the bastion host
resource "aws_instance" "wordpress_bastion_host" {
  ami           = var.ws_ami_id
  instance_type = var.bastion_instance_type
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  subnet_id = aws_subnet.public_subnets[0].id
  tags = {
    Name = "WordPressBastionHost"
  }
}

# Create an Elastic IP for the bastion host
resource "aws_eip" "wordpress_bastion_host_eip" {
  instance = aws_instance.wordpress_bastion_host.id
  vpc      = true
  tags = {
    Name = "WordPressBastionHostEIP"
  }
}

# Create an Auto Scaling group for the web server instances
resource "aws_autoscaling_group" "wordpress_web_server_asg" {
  name                      = "wordpress-web-server-asg"
  max_size                  = 5
  min_size                  = 2
  desired_capacity          = 2
  health_check_grace_period = 300
  health_check_type         = "EC2"
  launch_configuration      = aws_launch_configuration.wordpress_web_server_lc.name
  vpc_zone_identifier       = aws_subnet.private_subnets.*.id
  tags = {
    Name = "WordPressWebServerASG"
  }
}

# Create a launch configuration for the web server instances
resource "aws_launch_configuration" "wordpress_web_server_lc" {
  name          = "wordpress-web-server-lc"
  image_id      = var.ws_ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_server_sg.id]
  user_data = file("wordpress_user_data.sh")
  lifecycle {
    create_before_destroy = true
  }
}

# Output the ALB DNS name
output "alb_dns_name" {
  value = aws_lb.wordpress_alb.dns_name
}

# Output the CloudFront distribution domain name
output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
}

# Output the RDS instance endpoint
output "rds_instance_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}

# Output the S3 bucket name
output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3_bucket.id
}

# Output the Route 53 hosted zone ID
output "route53_hosted_zone_id" {
  value = aws_route53_zone.wordpress_zone.id
}
