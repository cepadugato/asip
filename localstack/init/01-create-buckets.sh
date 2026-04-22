#!/bin/bash
set -euo pipefail

echo "=== ASIP LocalStack: Creating S3 buckets ==="

# asip-backup — backup storage with versioning and lifecycle
awslocal s3 mb s3://asip-backup
awslocal s3api put-bucket-versioning \
  --bucket asip-backup \
  --versioning-configuration Status=Enabled
awslocal s3api put-bucket-lifecycle-configuration \
  --bucket asip-backup \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "ExpireAfter30Days",
      "Status": "Enabled",
      "Prefix": "",
      "Expiration": { "Days": 30 }
    }]
  }'
awslocal s3api put-bucket-encryption \
  --bucket asip-backup \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# asip-documents — document sync with longer retention
awslocal s3 mb s3://asip-documents
awslocal s3api put-bucket-versioning \
  --bucket asip-documents \
  --versioning-configuration Status=Enabled
awslocal s3api put-bucket-lifecycle-configuration \
  --bucket asip-documents \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "ExpireAfter90Days",
      "Status": "Enabled",
      "Prefix": "",
      "Expiration": { "Days": 90 }
    }]
  }'
awslocal s3api put-bucket-encryption \
  --bucket asip-documents \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

echo "S3 buckets created: asip-backup, asip-documents"