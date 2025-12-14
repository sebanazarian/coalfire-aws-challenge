#!/bin/bash

# Script to create EC2 Key Pair and configure terraform.tfvars

set -e

AWS_PROFILE="coalfire-challenge"
KEY_NAME="coalfire-challenge-key"

echo "🔑 Setting up EC2 Key Pair..."
echo "============================="
echo "Using AWS Profile: $AWS_PROFILE"
echo "Key Name: $KEY_NAME"
echo ""

# Check if profile exists
if ! aws configure list-profiles | grep -q "^${AWS_PROFILE}$"; then
    echo "❌ AWS profile '$AWS_PROFILE' not found!"
    echo "Available profiles:"
    aws configure list-profiles
    echo ""
    echo "Please set AWS_PROFILE environment variable or configure the profile:"
    echo "  aws configure --profile $AWS_PROFILE"
    exit 1
fi

# Check if key pair already exists
if aws ec2 describe-key-pairs --key-names $KEY_NAME --profile $AWS_PROFILE 2>/dev/null; then
    echo "✅ Key pair '$KEY_NAME' already exists"
else
    echo "Creating EC2 key pair: $KEY_NAME"
    aws ec2 create-key-pair --key-name $KEY_NAME --query 'KeyMaterial' --output text --profile $AWS_PROFILE > ${KEY_NAME}.pem
    chmod 400 ${KEY_NAME}.pem
    echo "✅ Key pair created and saved as ${KEY_NAME}.pem"
fi

# Create terraform.tfvars if it doesn't exist
if [ ! -f terraform.tfvars ]; then
    echo "Creating terraform.tfvars..."
    cp coalfire-aws-challenge/terraform.tfvars.example terraform.tfvars
    
    # Update key_name in terraform.tfvars
    sed -i "s/your-key-pair-name/$KEY_NAME/g" terraform.tfvars
    echo "✅ terraform.tfvars created with key_name = \"$KEY_NAME\""
else
    echo "⚠️  terraform.tfvars already exists"
    echo "Please ensure key_name = \"$KEY_NAME\" in your terraform.tfvars"
fi

echo ""
echo "✅ Setup complete!"