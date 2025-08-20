#!/bin/bash
# generate-keypair.sh - Generate SSH key pair for jump host

KEY_NAME="jumphost-key"
KEY_DIR="$HOME/.ssh"

echo "🔑 Generating SSH key pair for jump host..."

# Create .ssh directory if it doesn't exist
mkdir -p $KEY_DIR

# Generate key pair
ssh-keygen -t rsa -b 4096 -f "$KEY_DIR/$KEY_NAME" -N ""

echo "✅ SSH key pair generated:"
echo "Private key: $KEY_DIR/$KEY_NAME"
echo "Public key:  $KEY_DIR/$KEY_NAME.pub"
echo ""
echo "📋 Your public key (copy this to terraform.tfvars):"
cat "$KEY_DIR/$KEY_NAME.pub"
echo ""
echo "💾 Save the public key content to your terraform.tfvars file in the account-b directory."
