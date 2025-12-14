#!/bin/bash

# Script to create S3 bucket and DynamoDB table for Terraform backend

set -e

BUCKET_NAME="coalfire-challenge-terraform-state"
DYNAMODB_TABLE="coalfire-challenge-terraform-locks"
REGION="us-east-1"
AWS_PROFILE="coalfire-challenge"

echo "🔧 Setting up Terraform S3 Backend..."
echo "====================================="
echo "Using AWS Profile: $AWS_PROFILE"
echo "Region: $REGION"
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

# Create S3 bucket for state
echo "Creating S3 bucket: $BUCKET_NAME"
if aws s3api head-bucket --bucket $BUCKET_NAME --profile $AWS_PROFILE 2>/dev/null; then
    echo "✅ Bucket already exists"
else
    aws s3api create-bucket --bucket $BUCKET_NAME --region $REGION --profile $AWS_PROFILE
    echo "✅ Bucket created"
fi

# Enable versioning
echo "Enabling versioning on S3 bucket..."
aws s3api put-bucket-versioning --bucket $BUCKET_NAME --versioning-configuration Status=Enabled --profile $AWS_PROFILE

# Enable encryption
echo "Enabling encryption on S3 bucket..."
aws s3api put-bucket-encryption --bucket $BUCKET_NAME --server-side-encryption-configuration '{
  "Rules": [
    {
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }
  ]
}' --profile $AWS_PROFILE

# Block public access
echo "Blocking public access on S3 bucket..."
aws s3api put-public-access-block --bucket $BUCKET_NAME --public-access-block-configuration '{
  "BlockPublicAcls": true,
  "IgnorePublicAcls": true,
  "BlockPublicPolicy": true,
  "RestrictPublicBuckets": true
}' --profile $AWS_PROFILE

# Create DynamoDB table for state locking
echo "Creating DynamoDB table: $DYNAMODB_TABLE"
if aws dynamodb describe-table --table-name $DYNAMODB_TABLE --region $REGION --profile $AWS_PROFILE 2>/dev/null; then
    echo "✅ DynamoDB table already exists"
else
    aws dynamodb create-table \
      --table-name $DYNAMODB_TABLE \
      --attribute-definitions AttributeName=LockID,AttributeType=S \
      --key-schema AttributeName=LockID,KeyType=HASH \
      --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
      --region $REGION \
      --profile $AWS_PROFILE
    
    echo "⏳ Waiting for table to be active..."
    aws dynamodb wait table-exists --table-name $DYNAMODB_TABLE --region $REGION --profile $AWS_PROFILE
    echo "✅ DynamoDB table created"
fi

echo ""
echo "✅ Backend setup complete!"

