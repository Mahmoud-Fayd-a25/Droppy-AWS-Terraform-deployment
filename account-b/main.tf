# Account B - main.tf
# Deploy VPC B, Jump Host, Route53, and VPC Peering

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Provider for Account B
provider "aws" {
  alias   = "account_b"
  region  = var.aws_region
  profile = var.aws_profile_b
}

# Provider for Account A (for cross-account resources)
provider "aws" {
  alias   = "account_a"
  region  = var.aws_region
  profile = var.aws_profile_a
}

# Data sources
data "aws_caller_identity" "account_a" {
  provider = aws.account_a
}

data "aws_availability_zones" "available_b" {
  provider = aws.account_b
  state    = "available"
}

# Get the latest Windows Server 2022 AMI
data "aws_ami" "windows_2022" {
  provider    = aws.account_b
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Remote state data source to get Account A resources
data "terraform_remote_state" "account_a" {
  backend = "local"
  config = {
    path = "../account-a/terraform.tfstate"
  }
}

# VPC B
resource "aws_vpc" "vpc_b" {
  provider             = aws.account_b
  cidr_block           = var.vpc_b_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "vpc-b-jumphost"
  }
}

# Internet Gateway for VPC B
resource "aws_internet_gateway" "igw_b" {
  provider = aws.account_b
  vpc_id   = aws_vpc.vpc_b.id

  tags = {
    Name = "igw-vpc-b"
  }
}

# Public Subnet in VPC B
resource "aws_subnet" "public_b" {
  provider                = aws.account_b
  vpc_id                  = aws_vpc.vpc_b.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = data.aws_availability_zones.available_b.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-b"
    Type = "Public"
  }
}

# Route Table for VPC B
resource "aws_route_table" "public_b" {
  provider = aws.account_b
  vpc_id   = aws_vpc.vpc_b.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw_b.id
  }

  tags = {
    Name = "rt-public-b"
  }
}

# Route Table Association
resource "aws_route_table_association" "public_b" {
  provider       = aws.account_b
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_b.id
}

# VPC Peering Connection (initiated from Account B)
resource "aws_vpc_peering_connection" "vpc_peering" {
  provider      = aws.account_b
  vpc_id        = aws_vpc.vpc_b.id
  peer_vpc_id   = data.terraform_remote_state.account_a.outputs.vpc_a_id
  peer_region   = var.aws_region
  peer_owner_id = data.aws_caller_identity.account_a.account_id
  auto_accept   = false

  tags = {
    Name = "vpc-peering-b-to-a"
  }
}

# Accept VPC Peering Connection from Account A
resource "aws_vpc_peering_connection_accepter" "vpc_peering_accepter" {
  provider                  = aws.account_a
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc_peering.id
  auto_accept               = true

  tags = {
    Name = "vpc-peering-accepter"
  }
}

# Add routes for VPC peering in Account B
resource "aws_route" "vpc_b_to_vpc_a" {
  provider                  = aws.account_b
  route_table_id            = aws_route_table.public_b.id
  destination_cidr_block    = var.vpc_a_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc_peering.id
}

# Add routes for VPC peering in Account A (using remote state)
resource "aws_route" "vpc_a_public_to_vpc_b" {
  provider                  = aws.account_a
  route_table_id            = data.terraform_remote_state.account_a.outputs.public_route_table_id
  destination_cidr_block    = var.vpc_b_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc_peering.id
}

resource "aws_route" "vpc_a_private_to_vpc_b" {
  provider                  = aws.account_a
  route_table_id            = data.terraform_remote_state.account_a.outputs.private_route_table_id
  destination_cidr_block    = var.vpc_b_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc_peering.id
}

# Security Group for Jump Host
resource "aws_security_group" "jumphost_sg" {
  provider    = aws.account_b
  name        = "jumphost-sg"
  description = "Security group for Windows jump host"
  vpc_id      = aws_vpc.vpc_b.id

  # RDP access
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Restrict this to your IP for security
  }

  # HTTP access to VPC A resources
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_a_cidr]
  }

  # HTTPS access to VPC A resources
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_a_cidr]
  }

  # General internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "jumphost-security-group"
  }
}

# Key Pair for Jump Host (you'll need to create this)
resource "aws_key_pair" "jumphost_key" {
  provider   = aws.account_b
  key_name   = "jumphost-key"
  public_key = var.public_key # You'll need to provide this

  tags = {
    Name = "jumphost-key"
  }
}

# Windows Jump Host EC2 Instance
resource "aws_instance" "jumphost" {
  provider                    = aws.account_b
  ami                         = data.aws_ami.windows_2022.id
  instance_type               = "t3.medium"
  key_name                    = aws_key_pair.jumphost_key.key_name
  subnet_id                   = aws_subnet.public_b.id
  vpc_security_group_ids      = [aws_security_group.jumphost_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    <powershell>
    # Install Chrome
    $chromeUrl = "https://dl.google.com/chrome/install/latest/chrome_installer.exe"
    $chromeInstaller = "$env:TEMP\chrome_installer.exe"
    Invoke-WebRequest -Uri $chromeUrl -OutFile $chromeInstaller
    Start-Process -FilePath $chromeInstaller -Args "/silent /install" -Wait
    Remove-Item $chromeInstaller

    # Set timezone
    Set-TimeZone -Name "UTC"
    
    # Enable RDP
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -value 0
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
    </powershell>
  EOF

  tags = {
    Name = "windows-jumphost"
    OS   = "Windows Server 2022"
  }
}

# Route53 Private Hosted Zone
resource "aws_route53_zone" "droppy_zone" {
  provider = aws.account_b
  name     = "droppy.lan"

  vpc {
    vpc_id     = aws_vpc.vpc_b.id
    vpc_region = var.aws_region
  }

  tags = {
    Name = "droppy-private-zone"
  }
}

# Associate Route53 zone with VPC A
resource "aws_route53_zone_association" "vpc_a_association" {
  provider   = aws.account_a
  zone_id    = aws_route53_zone.droppy_zone.zone_id
  vpc_id     = data.terraform_remote_state.account_a.outputs.vpc_a_id
  vpc_region = var.aws_region
}

# DNS Record pointing to ALB in Account A
resource "aws_route53_record" "droppy_app" {
  provider = aws.account_b
  zone_id  = aws_route53_zone.droppy_zone.zone_id
  name     = "app.droppy.lan"
  type     = "A"

  alias {
    name                   = data.terraform_remote_state.account_a.outputs.alb_dns_name
    zone_id                = data.terraform_remote_state.account_a.outputs.alb_zone_id
    evaluate_target_health = true
  }
}
