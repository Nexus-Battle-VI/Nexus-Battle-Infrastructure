/**
 * Almacenamiento y ownership de recursos visuales de Producto (ADR-016 / EN-027.9).
 *
 * Bucket privado con Object Ownership BucketOwnerEnforced, sin acceso publico,
 * versionado habilitado, cifrado SSE-S3 con Bucket Key, rechazo de conexiones
 * sin TLS, ciclo de vida para staging y versiones antiguas, y alarmas de coste
 * preventivas en CloudWatch.
 */

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
  tags = merge(var.tags, {
    Component  = "catalog-assets"
    CostCenter = "product-assets"
  })

  lifecycle {
    # Los assets de producto no deben eliminarse en un destroy rutinario
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  depends_on = [aws_s3_bucket_versioning.this]

  rule {
    id     = "caducar-staging"
    status = "Enabled"

    filter {
      prefix = "staging/"
    }

    expiration {
      days = var.staging_retention_days
    }
  }

  rule {
    id     = "caducar-versiones-no-vigentes"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }
  }

  rule {
    id     = "abortar-multipartes-incompletas"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

data "aws_iam_policy_document" "solo_tls" {
  statement {
    sid    = "DenegarSinTLS"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.solo_tls.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

resource "aws_s3_bucket_metric" "this" {
  bucket = aws_s3_bucket.this.id
  name   = "EntireBucket"
}

resource "aws_cloudwatch_metric_alarm" "storage_bytes" {
  alarm_name        = "${var.bucket_name}-storage-bytes-5gb"
  alarm_description = "Alarma de volumen de almacenamiento de assets de producto (5 GB) para HU-33 / ADR-016."

  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BucketSizeBytes"
  namespace           = "AWS/S3"
  period              = 86400
  statistic           = "Average"
  threshold           = var.max_storage_bytes_alarm

  dimensions = {
    BucketName  = aws_s3_bucket.this.id
    StorageType = "StandardStorage"
  }

  alarm_actions = var.alarm_actions
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "download_bytes" {
  alarm_name        = "${var.bucket_name}-download-bytes-50gb"
  alarm_description = "Alarma de transferencia saliente de assets de producto (50 GB) para HU-33 / ADR-016."

  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BytesDownloaded"
  namespace           = "AWS/S3"
  period              = 86400
  statistic           = "Sum"
  threshold           = var.max_download_bytes_alarm

  dimensions = {
    BucketName = aws_s3_bucket.this.id
    FilterId   = aws_s3_bucket_metric.this.name
  }

  alarm_actions = var.alarm_actions
  tags          = var.tags
}
