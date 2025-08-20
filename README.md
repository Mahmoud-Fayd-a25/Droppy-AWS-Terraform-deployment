# Multi-Account Droppy Deployment on AWS ECS

This Terraform configuration deploys Droppy file manager across two AWS accounts with the following architecture:

## Architecture Overview

### Account A (Application Account)

- **VPC A** (10.0.0.0/16)
  - 2 Public subnets (10.0.1.0/24, 10.0.2.0/24)
  - 2 Private Load Balancer subnets (10.0.10.0/24, 10.0.11.0/24)
  - 2 Private ECS subnets (10.0.20.0/24, 10.0.21.0/24)
  - 2 Intra subnets for EFS (10.0.30.0/24, 10.0.31.0/24)
- **ECS Fargate** cluster running Droppy with 2 replicas
- **Internal ALB** in private subnets
- **EFS** for persistent storage
- **NAT Gateway** for outbound internet access

### Account B (Access Account)

- **VPC B** (10.1.0.0/23)
  - 1 Public subnet (10.1.1.0/24)
- **Windows Jump Host** for accessing Droppy
- **Route53 Private Hosted Zone** (droppy.lan)
- **VPC Peering** connection to Account A

## Deployment Steps

### Prerequisites

1. Two AWS accounts configured with CLI profiles
2. SSH key pair for the jump host
3. Terraform >= 1.5 installed

### Step 1: Configure AWS CLI Profiles

```bash
# Configure Account A profile
aws configure --profile account-a
# Enter Access Key ID, Secret Access Key, Region

# Configure Account B profile
aws configure --profile account-b
# Enter Access Key ID, Secret Access Key, Region
```

### Step 2: Generate SSH Key Pair

```bash
# Generate key pair for jump host
ssh-keygen -t rsa -b 4096 -f ~/.ssh/jumphost-key
# Copy the public key content for terraform.tfvars
cat ~/.ssh/jumphost-key.pub
```

### Step 3: Deploy Account A Infrastructure

```bash
cd account-a
# Create terraform.tfvars file with your values
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Initialize and deploy
terraform init
terraform plan
terraform apply
```

### Step 4: Deploy Account B Infrastructure

```bash
cd ../account-b
# Create terraform.tfvars file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Initialize and deploy
terraform init
terraform plan
terraform apply
```

### Step 5: Access Droppy

1. RDP to the Windows jump host using the public IP
2. Open a web browser on the jump host
3. Navigate to: `http://app.droppy.lan`

## Configuration Files

- `shared/`: Common configurations and modules
- `account-a/`: Account A specific resources (ECS, ALB, EFS)
- `account-b/`: Account B specific resources (Jump host, Route53)
- `scripts/`: Automation scripts for deployment

## Security Considerations

1. **Jump Host Access**: Restrict RDP access to specific IP ranges
2. **Internal ALB**: Load balancer is internal-only, not internet-facing
3. **EFS Encryption**: EFS filesystem is encrypted at rest
4. **Security Groups**: Minimal required access between components

## Troubleshooting

### Common Issues

1. **VPC Peering**: Ensure both accounts accept the peering connection
2. **DNS Resolution**: Verify Route53 zone is associated with both VPCs
3. **Security Groups**: Check that security group rules allow traffic flow
4. **EFS Mount**: Ensure EFS mount targets are in the correct subnets

### Useful Commands

```bash
# Check ECS service status
aws ecs describe-services --cluster droppy-cluster --services droppy-service --profile account-a

# Check ALB targets
aws elbv2 describe-target-health --target-group-arn <target-group-arn> --profile account-a

# Check Route53 records
aws route53 list-resource-record-sets --hosted-zone-id <zone-id> --profile account-b
```

## Clean Up

```bash
# Destroy resources in reverse order
cd account-b
terraform destroy

cd ../account-a
terraform destroy
```
