# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Define variables for the configuration
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "The availability zones for the subnets"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "The instance type for the EC2 instances"
}

variable "database_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "The instance class for the RDS instance"
}

variable "elasticache_node_type" {
  type        = string
  default     = "cache.t2.micro"
  description = "The node type for the Elasticache cluster"
}

variable "cloudfront_ssl_certificate" {
  type        = string
  default     = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  description = "The SSL certificate for the CloudFront distribution"
}

variable "route53_domain_name" {
  type        = string
  default     = "example.com"
  description = "The domain name for the Route 53 hosted zone"
}

# Create the VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the subnets
resource "aws_subnet" "public_subnets" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PublicSubnet${count.index + 1}"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, length(var.availability_zones) + count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PrivateSubnet${count.index + 1}"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the route tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the route table associations
resource "aws_route_table_association" "public_subnets" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnets" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Create the security groups
resource "aws_security_group" "web_server_sg" {
  name        = "WordPressWebServerSG"
  description = "Security group for the web server"
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
    cidr_blocks = ["10.0.0.0/16"]
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
    Project     = "wordpress"
  }
}

resource "aws_security_group" "database_sg" {
  name        = "WordPressDatabaseSG"
  description = "Security group for the database"
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
    Name        = "WordPressDatabaseSG"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.web_server_sg.id]
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
    ssl_certificate_id = var.cloudfront_ssl_certificate
  }
  tags = {
    Name        = "WordPressELB"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the RDS instance
resource "aws_db_instance" "wordpress_db" {
  identifier           = "wordpress-db"
  instance_class       = var.database_instance_class
  engine               = "mysql"
  engine_version       = "8.0.20"
  username             = "wordpress"
  password             = "password123"
  vpc_security_group_ids = [aws_security_group.database_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  tags = {
    Name        = "WordPressDB"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the DB subnet group
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private_subnets.*.id
  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the Elasticache cluster
resource "aws_elasticache_cluster" "wordpress_cache" {
  cluster_id           = "wordpress-cache"
  engine               = "memcached"
  node_type            = var.elasticache_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.memcached1.4"
  port                 = 11211
  subnet_group_name   = aws_elasticache_subnet_group.wordpress_cache_subnet_group.name
  tags = {
    Name        = "WordPressCache"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the Elasticache subnet group
resource "aws_elasticache_subnet_group" "wordpress_cache_subnet_group" {
  name       = "wordpress-cache-subnet-group"
  subnet_ids = aws_subnet.private_subnets.*.id
  tags = {
    Name        = "WordPressCacheSubnetGroup"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [var.route53_domain_name]
  viewer_certificate {
    acm_certificate_arn = var.cloudfront_ssl_certificate
    ssl_support_method  = "sni-only"
  }
  tags = {
    Name        = "WordPressDistribution"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the S3 bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = var.route53_domain_name
  acl    = "private"
  tags = {
    Name        = "WordPressBucket"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the Route 53 hosted zone
resource "aws_route53_zone" "wordpress_zone" {
  name = var.route53_domain_name
  tags = {
    Name        = "WordPressZone"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the Route 53 record
resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = var.route53_domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_distribution.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_distribution.zone_id
    evaluate_target_health = false
  }
}

# Create the EC2 instances
resource "aws_instance" "wordpress_instances" {
  count         = 2
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  subnet_id = aws_subnet.public_subnets[count.index].id
  tags = {
    Name        = "WordPressInstance${count.index + 1}"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the Auto Scaling group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  max_size                  = 5
  min_size                  = 2
  desired_capacity          = 2
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id
  tags = {
    Name        = "WordPressASG"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Create the launch configuration
resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_server_sg.id]
  user_data = file("${path.module}/user_data.sh")
  lifecycle {
    create_before_destroy = true
  }
}

# Output the ELB DNS name
output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

# Output the CloudFront distribution domain name
output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_distribution.domain_name
}

# Output the Route 53 hosted zone ID
output "route53_hosted_zone_id" {
  value = aws_route53_zone.wordpress_zone.zone_id
}

# Output the S3 bucket name
output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_bucket.bucket
}
