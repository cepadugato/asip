#!/bin/bash
set -euo pipefail

echo "=== ASIP LocalStack: Creating IAM users and policies ==="

# --- asip-backup-agent: full access to asip-backup bucket only ---
awslocal iam create-user --user-name asip-backup-agent

awslocal iam put-user-policy \
  --user-name asip-backup-agent \
  --policy-name AsipBackupPolicy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::asip-backup",
        "arn:aws:s3:::asip-backup/*"
      ]
    }]
  }'

BACKUP_KEY=$(awslocal iam create-access-key --user-name asip-backup-agent \
  --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text)
echo "asip-backup-agent credentials: ${BACKUP_KEY}"

# --- asip-docs-sync: put/get/list on asip-documents ---
awslocal iam create-user --user-name asip-docs-sync

awslocal iam put-user-policy \
  --user-name asip-docs-sync \
  --policy-name AsipDocsSyncPolicy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ],
        "Resource": [
          "arn:aws:s3:::asip-documents",
          "arn:aws:s3:::asip-documents/*"
        ]
      }
    ]
  }'

DOCS_KEY=$(awslocal iam create-access-key --user-name asip-docs-sync \
  --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text)
echo "asip-docs-sync credentials: ${DOCS_KEY}"

# --- asip-cross-account-role: assume role for cross-account scenarios ---
awslocal iam create-role \
  --role-name asip-cross-account-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::000000000000:root"},
      "Action": "sts:AssumeRole"
    }]
  }'

awslocal iam put-role-policy \
  --role-name asip-cross-account-role \
  --policy-name AsipCrossAccountPolicy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::asip-backup",
        "arn:aws:s3:::asip-backup/*"
      ]
    }]
  }'

echo "IAM users and policies created: asip-backup-agent, asip-docs-sync, asip-cross-account-role"