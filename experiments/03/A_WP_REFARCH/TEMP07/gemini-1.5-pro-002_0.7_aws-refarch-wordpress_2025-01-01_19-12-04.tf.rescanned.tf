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
  description = "The AWS region to deploy resources in."
  default     = "us-west-2"
}

variable "project_name" {
  type        = string
  description = "The name of the project."
  default     = "wordpress-project"
}

variable "environment" {
  type        = string
  description = "The environment name (e.g., dev, prod)."
  default     = "dev"
}

# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  }
}


resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.flow_log_role.arn
  log_destination = aws_cloudwatch_log_group.flow_log_group.arn
 traffic_type   = "ALL"
  vpc_id         = aws_vpc.main.id
  max_aggregation_interval = 600

  tags = {
    Name        = "${var.project_name}-flow-log"
    Environment = var.environment
  }

}

resource "aws_iam_role" "flow_log_role" {
  name = "${var.project_name}-flow-logs-role"
 assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
  {
   "Action": "sts:AssumeRole",
   "Principal": {
    "Service": "vpc-flow-logs.amazonaws.com"
   },
   "Effect": "Allow",
   "Sid": ""
  }
 ]
}
EOF

  tags = {
    Name = "${var.project_name}-flow-logs-role"
 Environment = var.environment
  }
}


resource "aws_iam_role_policy_attachment" "flow_log_policy" {
 policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonVPCFlowLogsRole"
 role       = aws_iam_role.flow_log_role.name
}


resource "aws_cloudwatch_log_group" "flow_log_group" {
  name              = "/aws/flowlogs/${var.project_name}"
  retention_in_days = 7
}


resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
 map_public_ip_on_launch = false # Updated to false for security

  tags = {
    Name        = "${var.project_name}-public-subnet-1"
    Environment = var.environment
  }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "${var.project_name}-private-subnet-1"
    Environment = var.environment
  }
}


resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
  }
}

resource "aws_route_table" "public_route_table" {
 vpc_id = aws_vpc.main.id

 route {
   cidr_block = "0.0.0.0/0"
   gateway_id = aws_internet_gateway.gw.id
 }

 tags = {
   Name        = "${var.project_name}-public-route-table"
   Environment = var.environment
 }
}


resource "aws_route_table_association" "public_subnet_association" {
 subnet_id      = aws_subnet.public_1.id
 route_table_id = aws_route_table.public_route_table.id
}


data "aws_availability_zones" "available" {}

# Security Groups - Add security groups here


# EC2, RDS, ALB, ASG, CloudFront, S3, Route53 (Simplified examples due to space constraints)

output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC."
}

