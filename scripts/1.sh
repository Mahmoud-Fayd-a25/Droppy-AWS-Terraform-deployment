#!/bin/bash

chmod +x scripts/deploy.sh
chmod +x scripts/cleanup.sh
chmod +x scripts/generate-keypair.sh

echo "📁 Final Directory Structure:"
tree 2>/dev/null || find . -type d -exec echo "Directory: {}" \; -o -type f -exec echo "File: {}" \;
echo ""
echo "🚀 Quick Start:"
echo "1. Generate SSH key pair:"
echo "   ./scripts/generate-keypair.sh"
echo ""
echo "2. Configure AWS profiles:"
echo "   aws configure --profile account-a"
echo "   aws configure --profile account-b"
echo ""
echo "3. Deploy everything:"
echo "   ./scripts/deploy.sh"
echo ""
echo "Or deploy manually:"
echo "4a. Deploy Account A:"
echo "    cd account-a"
echo "    terraform init && terraform apply"
echo ""
echo "4b. Deploy Account B:"
echo "    cd ../account-b"
echo "    # Edit terraform.tfvars (add your public key!)"
echo "    terraform init && terraform apply"

# Basic deployment with prompts
./deploy.sh

# Automated deployment (CI/CD friendly)
./deploy.sh --auto-approve

# Debug mode with extended timeout
./deploy.sh --debug --timeout 7200

# Dry run to preview changes
./deploy.sh --dry-run

# Custom configuration
./deploy.sh --config production.config