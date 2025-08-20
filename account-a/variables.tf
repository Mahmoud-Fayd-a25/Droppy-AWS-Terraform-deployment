variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "aws_profile_a" {
  description = "AWS CLI profile for Account A"
  type        = string
  default     = "account-a"
}

variable "vpc_a_cidr" {
  description = "CIDR block for VPC A"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_b_cidr" {
  description = "CIDR block for VPC B"
  type        = string
  default     = "10.1.0.0/23"
}
