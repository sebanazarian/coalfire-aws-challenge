#!/bin/bash

# Script to create required S3 folders after deployment

set -e

AWS_PROFILE="coalfire-challenge"

echo "📁 Creating S3 Folders..."
echo "========================="
echo "Using AWS Profile: $AWS_PROFILE"
echo ""

# Check if profile exists
if ! aws configure list-profiles | grep -q "^${AWS_PROFILE}$"; then
    echo "❌ AWS profile '$AWS_PROFILE' not found!"
    echo "Available profiles:"
    aws configure list-profiles
    exit 1
fi

# Get bucket names from Terraform outputs
IMAGES_BUCKET=$(terraform output -raw images_bucket_name)
LOGS_BUCKET=$(terraform output -raw logs_bucket_name)

echo "Images Bucket: $IMAGES_BUCKET"
echo "Logs Bucket: $LOGS_BUCKET"

# Create archive folder in images bucket
echo "Creating archive/ folder in images bucket..."
aws s3api put-object --bucket $IMAGES_BUCKET --key archive/ --content-length 0 --profile $AWS_PROFILE

# Create active and inactive folders in logs bucket
echo "Creating active/ folder in logs bucket..."
aws s3api put-object --bucket $LOGS_BUCKET --key active/ --content-length 0 --profile $AWS_PROFILE

echo "Creating inactive/ folder in logs bucket..."
aws s3api put-object --bucket $LOGS_BUCKET --key inactive/ --content-length 0 --profile $AWS_PROFILE

echo "✅ S3 folders created successfully!"
echo ""
echo "Folder structure:"
echo "📁 $IMAGES_BUCKET"
echo "  └── archive/"
echo "📁 $LOGS_BUCKET"
echo "  ├── active/"
echo "  └── inactive/"
