terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  access_key                  = "test"
  secret_key                  = "test"
  region                      = var.aws_region
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3  = "http://localhost:4566"
    iam = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

resource "aws_s3_bucket" "asip_backup" {
  bucket = "asip-backup"

  tags = {
    Name        = "ASIP Backup"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "asip_backup" {
  bucket = aws_s3_bucket.asip_backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "asip_backup" {
  bucket = aws_s3_bucket.asip_backup.id

  rule {
    id     = "ExpireAfter30Days"
    status = "Enabled"

    expiration {
      days = 30
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "asip_backup" {
  bucket = aws_s3_bucket.asip_backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket" "asip_documents" {
  bucket = "asip-documents"

  tags = {
    Name        = "ASIP Documents"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "asip_documents" {
  bucket = aws_s3_bucket.asip_documents.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "asip_documents" {
  bucket = aws_s3_bucket.asip_documents.id

  rule {
    id     = "ExpireAfter90Days"
    status = "Enabled"

    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "asip_documents" {
  bucket = aws_s3_bucket.asip_documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_user" "backup_agent" {
  name = "asip-backup-agent"
}

resource "aws_iam_access_key" "backup_agent" {
  user = aws_iam_user.backup_agent.name
}

resource "aws_iam_user_policy" "backup_agent" {
  name = "AsipBackupPolicy"
  user = aws_iam_user.backup_agent.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation"]
      Resource = [
        aws_s3_bucket.asip_backup.arn,
        "${aws_s3_bucket.asip_backup.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_user" "docs_sync" {
  name = "asip-docs-sync"
}

resource "aws_iam_access_key" "docs_sync" {
  user = aws_iam_user.docs_sync.name
}

resource "aws_iam_user_policy" "docs_sync" {
  name = "AsipDocsSyncPolicy"
  user = aws_iam_user.docs_sync.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [
        aws_s3_bucket.asip_documents.arn,
        "${aws_s3_bucket.asip_documents.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_role" "cross_account" {
  name = "asip-cross-account-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { AWS = "arn:aws:iam::000000000000:root" }
      Action   = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "cross_account" {
  name = "AsipCrossAccountPolicy"
  role = aws_iam_role.cross_account.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:ListBucket"]
      Resource = [
        aws_s3_bucket.asip_backup.arn,
        "${aws_s3_bucket.asip_backup.arn}/*"
      ]
    }]
  })
}

data "aws_caller_identity" "current" {}

output "is_localstack" {
  value = data.aws_caller_identity.current.id == "000000000000"
}

output "s3_buckets" {
  value = {
    backup    = aws_s3_bucket.asip_backup.bucket
    documents = aws_s3_bucket.asip_documents.bucket
  }
}

output "iam_users" {
  value = {
    backup_agent_access_key = aws_iam_access_key.backup_agent.id
    docs_sync_access_key    = aws_iam_access_key.docs_sync.id
  }
}

output "cross_account_role_arn" {
  value = aws_iam_role.cross_account.arn
}