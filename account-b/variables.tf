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

variable "aws_profile_b" {
  description = "AWS CLI profile for Account B"
  type        = string
  default     = "account-b"
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

variable "public_key" {
  description = "Public key for EC2 key pair"
  type        = string
  # You'll need to provide this value in terraform.tfvars
}

variable "allowed_rdp_cidr" {
  description = "CIDR block allowed for RDP access to jump host"
  type        = string
  default     = "0.0.0.0/0" # Change this to your IP for security
}
