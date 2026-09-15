output "queue_url" {
  description = "URL de la cola principal de catalog.product.created (CATALOG_QUEUE_URL en Notifications; nombre recomendado para el futuro dispatcher de Catalog)."
  value       = aws_sqs_queue.main.id
}

output "queue_arn" {
  description = "ARN de la cola principal, para politicas IAM de Catalog (SendMessage) y Notifications (Receive/Delete/ChangeMessageVisibility/GetQueueAttributes)."
  value       = aws_sqs_queue.main.arn
}

output "queue_name" {
  value = aws_sqs_queue.main.name
}

output "dlq_url" {
  description = "URL de la DLQ. Su consumo es administrativo (redrive), no un ARN que Catalog o Notifications necesiten en su configuracion de aplicacion."
  value       = aws_sqs_queue.dlq.id
}

output "dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}

output "dlq_name" {
  value = aws_sqs_queue.dlq.name
}
