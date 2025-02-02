provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  default = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "instance_type" {
  default = "t2.micro"
}

variable "ami_id" {
  default = "ami-0c55b159cbfafe1f0" # Amazon Linux 2
}

variable "rds_instance_class" {
  default = "db.t2.small"
}

variable "rds_engine" {
  default = "mysql"
}

variable "rds_username" {
  default = "wordpress"
}

variable "rds_password" {
  sensitive = true
}

variable "cloudfront_distribution_bucket" {
  default = "wordpress-static-assets"
}

variable "cloudfront_distribution_comment" {
  default = "WordPress static assets distribution"
}

variable "route53_zone_name" {
  default = "example.com"
}

variable "route53_record_name" {
  default = "wordpress"
}

variable "efs_performance_mode" {
  default = "generalPurpose"
}

variable "efs_transition_to_ia" {
  default = true
}

variable "elasticache_engine" {
  default = "memcached"
}

variable "elasticache_node_type" {
  default = "cache.t2.micro"
}

variable "elasticache_num_nodes" {
  default = 1
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "WordPressVPC"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_subnet" "public_subnets" {
  count = length(var.availability_zones)
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "PublicSubnet${count.index + 1}"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_subnet" "private_subnets" {
  count = length(var.availability_zones)
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, length(var.availability_zones) + count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PrivateSubnet${count.index + 1}"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicRouteTable"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_route" "public_route" {
  route_table_id = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateRouteTable"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_route_table_association" "public_subnets" {
  count = length(aws_subnet.public_subnets)
  subnet_id = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnets" {
  count = length(aws_subnet.private_subnets)
  subnet_id = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_security_group" "wordpress_sg" {
  name = "WordPressSG"
  description = "Security group for WordPress instances"
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "WordPressSG"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_security_group" "rds_sg" {
  name = "RDSSG"
  description = "Security group for RDS instance"
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "RDSSG"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_instance" "wordpress_instance" {
  ami = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  subnet_id = aws_subnet.public_subnets[0].id
  key_name = "wordpress"
  tags = {
    Name = "WordPressInstance"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_db_instance" "wordpress_db" {
  allocated_storage = 20
  engine = var.rds_engine
  engine_version = "8.0.23"
  instance_class = var.rds_instance_class
  name = "wordpressdb"
  username = var.rds_username
  password = var.rds_password
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  multi_az = true
  tags = {
    Name = "WordPressDB"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name = "wordpress_db_subnet_group"
  subnet_ids = aws_subnet.private_subnets.*.id
  tags = {
    Name = "WordPressDBSubnetGroup"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_elb" "wordpress_elb" {
  name = "WordPressELB"
  subnets = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_sg.id]
  listener {
    instance_port = 80
    instance_protocol = "http"
    lb_port = 80
    lb_protocol = "http"
  }
  listener {
    instance_port = 443
    instance_protocol = "https"
    lb_port = 443
    lb_protocol = "https"
    ssl_certificate_id = "arn:aws:iam::123456789012:server-certificate/WordPressELBCertificate"
  }
  tags = {
    Name = "WordPressELB"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_autoscaling_group" "wordpress_autoscaling_group" {
  name = "WordPressAutoscalingGroup"
  max_size = 5
  min_size = 1
  desired_capacity = 1
  launch_configuration = aws_launch_configuration.wordpress_launch_configuration.name
  vpc_zone_identifier = aws_subnet.public_subnets[0].id
  tags = {
    Name = "WordPressAutoscalingGroup"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name = "WordPressLaunchConfiguration"
  image_id = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.wordpress_sg.id]
  key_name = "wordpress"
  user_data = file("${path.module}/user_data.sh")
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudfront_distribution" "wordpress_cloudfront_distribution" {
  origin {
    domain_name = aws_s3_bucket.wordpress_static_assets.bucket_regional_domain_name
    origin_id = "WordPressStaticAssets"
  }
  enabled = true
  default_root_object = "index.html"
  aliases = [var.route53_record_name]
  viewer_certificate {
    acm_certificate_arn = "arn:aws:iam::123456789012:certificate/WordPressCloudFrontCertificate"
    ssl_support_method = "sni-only"
  }
  default_cache_behavior {
    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods = ["GET", "HEAD"]
    target_origin_id = "WordPressStaticAssets"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "allow-all"
    min_ttl = 0
    default_ttl = 3600
    max_ttl = 86400
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  tags = {
    Name = "WordPressCloudFrontDistribution"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_s3_bucket" "wordpress_static_assets" {
  bucket = var.cloudfront_distribution_bucket
  acl = "private"
  force_destroy = true
  tags = {
    Name = "WordPressStaticAssets"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name = var.route53_record_name
  type = "A"
  alias {
    name = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
    zone_id = aws_cloudfront_distribution.wordpress_cloudfront_distribution.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "wordpress_route53_zone" {
  name = var.route53_zone_name
  tags = {
    Name = "WordPressRoute53Zone"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_efs_file_system" "wordpress_efs_file_system" {
  creation_token = "wordpress-efs-file-system"
  performance_mode = var.efs_performance_mode
  lifecycle_policy {
    transition_to_ia = var.efs_transition_to_ia
  }
  tags = {
    Name = "WordPressEFSFileSystem"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_efs_mount_target" "wordpress_efs_mount_target" {
  count = length(aws_subnet.private_subnets)
  file_system_id = aws_efs_file_system.wordpress_efs_file_system.id
  subnet_id = aws_subnet.private_subnets[count.index].id
  security_groups = [aws_security_group.wordpress_sg.id]
}

resource "aws_elasticache_cluster" "wordpress_elasticache_cluster" {
  cluster_id = "wordpress-elasticache-cluster"
  engine = var.elasticache_engine
  node_type = var.elasticache_node_type
  num_cache_nodes = var.elasticache_num_nodes
  parameter_group_name = "default.memcached1.4"
  port = 11211
  subnet_group_name = aws_elasticache_subnet_group.wordpress_elasticache_subnet_group.name
  tags = {
    Name = "WordPressElasticacheCluster"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_elasticache_subnet_group" "wordpress_elasticache_subnet_group" {
  name = "wordpress-elasticache-subnet-group"
  subnet_ids = aws_subnet.private_subnets.*.id
  tags = {
    Name = "WordPressElasticacheSubnetGroup"
    Environment = "Production"
    Project = "WordPress"
  }
}

output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
}

output "wordpress_route53_record_name" {
  value = aws_route53_record.wordpress_route53_record.name
}

output "wordpress_efs_file_system_id" {
  value = aws_efs_file_system.wordpress_efs_file_system.id
}

output "wordpress_elasticache_cluster_id" {
  value = aws_elasticache_cluster.wordpress_elasticache_cluster.cluster_id
}
