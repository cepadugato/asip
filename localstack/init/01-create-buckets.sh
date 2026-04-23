#!/bin/bash
set -euo pipefail

AWS="aws --endpoint-url=http://localhost:4566 --region eu-west-1"

echo "=== ASIP LocalStack: Creating S3 buckets ==="

# asip-backup — backup storage with versioning and encryption
$AWS s3 mb s3://asip-backup 2>/dev/null || echo "Bucket asip-backup already exists"
$AWS s3api put-bucket-versioning \
  --bucket asip-backup \
  --versioning-configuration Status=Enabled 2>/dev/null || true
$AWS s3api put-bucket-encryption \
  --bucket asip-backup \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }' 2>/dev/null || true

# asip-documents — document sync with versioning and encryption
$AWS s3 mb s3://asip-documents 2>/dev/null || echo "Bucket asip-documents already exists"
$AWS s3api put-bucket-versioning \
  --bucket asip-documents \
  --versioning-configuration Status=Enabled 2>/dev/null || true
$AWS s3api put-bucket-encryption \
  --bucket asip-documents \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }' 2>/dev/null || true

# asip-terraform-state — Terraform state backend
$AWS s3 mb s3://asip-terraform-state 2>/dev/null || echo "Bucket asip-terraform-state already exists"

echo "S3 buckets created: asip-backup, asip-documents, asip-terraform-state"