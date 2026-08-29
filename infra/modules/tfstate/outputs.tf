output "bucket" {
  description = "Nombre del bucket, para el bloque `backend` de `versions.tf`."
  value       = aws_s3_bucket.this.id
}

output "arn" {
  value = aws_s3_bucket.this.arn
}
