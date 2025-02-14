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
  type        = string
  description = "The AWS region to deploy into."
  default     = "us-west-2"
}

variable "vpc_cidr" {
  type        = string
  description = "The CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "The CIDR blocks for the public subnets."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "The CIDR blocks for the private subnets."
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "availability_zones" {
  type        = list(string)
  description = "The availability zones for the subnets."
  default     = ["us-west-2a", "us-west-2b"]
}

variable "instance_type" {
  type        = string
  description = "The EC2 instance type."
  default     = "t3.micro"
}

variable "db_instance_class" {
  type        = string
  description = "The RDS instance class."
  default     = "db.t3.micro"
}


resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "wordpress-vpc"
    Environment = "production"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "wordpress-igw"
    Environment = "production"
  }
}

resource "aws_flow_log" "main" {
  vpc_id = aws_vpc.main.id
  traffic_type = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_group_name = "/aws/flowlogs/wordpress-vpc"
}


output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC."
}

output "alb_dns_name" {
  value       = aws_lb.main.dns_name # Assuming aws_lb.main exists based on the original code.
  description = "The DNS name of the application load balancer."
}


