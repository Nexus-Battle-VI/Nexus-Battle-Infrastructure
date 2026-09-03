output "bucket_id" {
  description = "Nombre e identificador del bucket de assets de producto."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN del bucket de assets de producto."
  value       = aws_s3_bucket.this.arn
}
