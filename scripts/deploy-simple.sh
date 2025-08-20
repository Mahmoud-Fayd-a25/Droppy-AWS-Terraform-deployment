#!/bin/bash
# deploy.sh - Automated deployment script

set -e

echo "🚀 Starting multi-account Droppy deployment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    print_error "Terraform is not installed. Please install Terraform first."
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed. Please install AWS CLI first."
    exit 1
fi

print_status "Deploying Account A infrastructure..."
cd account-a

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    print_warning "terraform.tfvars not found in account-a. Copying from example..."
    cp terraform.tfvars.example terraform.tfvars
    print_warning "Please edit account-a/terraform.tfvars with your values before continuing."
    read -p "Press Enter to continue after editing terraform.tfvars..."
fi

# Initialize and deploy Account A
terraform init
terraform validate
terraform plan -out=tfplan-account-a
terraform apply tfplan-account-a

print_status "Account A deployment completed successfully!"

print_status "Deploying Account B infrastructure..."
cd ../account-b

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    print_warning "terraform.tfvars not found in account-b. Copying from example..."
    cp terraform.tfvars.example terraform.tfvars
    print_warning "Please edit account-b/terraform.tfvars with your values before continuing."
    print_warning "Don't forget to add your SSH public key!"
    read -p "Press Enter to continue after editing terraform.tfvars..."
fi

# Initialize and deploy Account B
terraform init
terraform validate
terraform plan -out=tfplan-account-b
terraform apply tfplan-account-b

print_status "Account B deployment completed successfully!"

cd ..

# Get outputs
print_status "Getting deployment outputs..."
JUMPHOST_IP=$(cd account-b && terraform output -raw jumphost_public_ip)
DROPPY_URL=$(cd account-b && terraform output -raw droppy_url)

echo ""
echo "🎉 Deployment completed successfully!"
echo ""
echo "📋 Connection Details:"
echo "Jump Host Public IP: $JUMPHOST_IP"
echo "Droppy URL (from jump host): $DROPPY_URL"
echo ""
echo "🔗 Next Steps:"
echo "1. RDP to the jump host: $JUMPHOST_IP"
echo "2. Open a web browser on the jump host"
echo "3. Navigate to: $DROPPY_URL"
echo ""
echo "⚠️  Security Note:"
echo "Consider restricting RDP access to your IP range in the security group."
