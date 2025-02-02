terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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

variable "name_prefix" {
  type    = string
  default = "wordpress-secure"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}


# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "${var.name_prefix}-vpc"
    Environment = "production"
  }
}


# Security Groups


# EC2 Instances and Auto Scaling


# RDS Instance


# Elastic Load Balancer


# CloudFront Distribution


# S3 Bucket



# Route 53 Configuration



# Outputs

