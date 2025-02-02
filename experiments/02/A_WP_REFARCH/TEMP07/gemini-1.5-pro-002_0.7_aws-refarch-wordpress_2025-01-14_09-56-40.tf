terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2" # Replace with your desired region
}

# VPC and Networking
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags        = {
    Name = "wordpress-vpc"
  }
}


# Security Groups


# EC2 Instances


# RDS Instance



# Elastic Load Balancer



# Auto Scaling Group


# CloudFront Distribution


# S3 Bucket


# Route 53 DNS Configuration





