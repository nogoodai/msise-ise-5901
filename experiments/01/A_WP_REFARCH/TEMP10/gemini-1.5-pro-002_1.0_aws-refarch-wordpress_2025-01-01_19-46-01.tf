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

variable "environment" {
  type    = string
  default = "development"
}

variable "project" {
  type    = string
  default = "wordpress-project"
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

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "rds_instance_type" {
  type    = string
  default = "db.t3.micro"
}

variable "rds_username" {
  type    = string
  default = "admin"
}

variable "rds_password" {
  type    = string
  sensitive = true
}

# ... (Other variables as needed, e.g., AMI IDs, key pair name)

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags        = {
    Name        = "wordpress-vpc-${var.environment}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "public_subnets" {
  for_each = toset(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = each.value
  availability_zone = data.aws_availability_zones.available.names[index(var.public_subnet_cidrs, each.value)]

  tags = {
    Name        = "wordpress-public-subnet-${index(var.public_subnet_cidrs, each.value)}-${var.environment}"
    Environment = var.environment
    Project     = var.project
  }
}

# ... (Other resources like private subnets, internet gateway, route tables, security groups, EC2 instances, RDS instance, ALB, ASG, CloudFront, S3, Route53)


data "aws_availability_zones" "available" {}

output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

# ... (Other outputs like ALB DNS name, RDS endpoint, etc.)


resource "aws_s3_bucket" "wordpress_assets" {

  bucket = "wordpress-assets-${var.environment}-${random_id.bucket_suffix.hex}"
  acl    = "private"

  tags = {
    Name        = "wordpress-assets-bucket-${var.environment}"
    Environment = var.environment
    Project     = var.project
  }

 lifecycle {
    prevent_destroy = false
  }
}


resource "random_id" "bucket_suffix" {
  byte_length = 8
}

resource "aws_cloudfront_distribution" "wordpress_cdn" {
 origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.wordpress_assets.bucket
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.wordpress_assets.bucket

 viewer_protocol_policy = "redirect-to-https"
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
    Name        = "wordpress-cloudfront-${var.environment}"
    Environment = var.environment
 Project     = var.project
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
  tags = {
    Name        = "wordpress-route53-${var.environment}"
    Environment = var.environment
    Project     = var.project
  }
}


variable "domain_name" {
  type    = string


}
