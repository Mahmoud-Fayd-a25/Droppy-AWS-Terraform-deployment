#!/bin/bash
# cleanup.sh - Script to destroy all resources

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning "This will destroy ALL resources in both accounts!"
read -p "Are you sure you want to continue? (yes/no): " confirm

if [[ $confirm != "yes" ]]; then
    print_status "Cleanup cancelled."
    exit 0
fi

print_status "Destroying Account B resources..."
cd account-b
terraform destroy -auto-approve

print_status "Destroying Account A resources..."
cd ../account-a
terraform destroy -auto-approve

cd ..
print_status "All resources have been destroyed."
