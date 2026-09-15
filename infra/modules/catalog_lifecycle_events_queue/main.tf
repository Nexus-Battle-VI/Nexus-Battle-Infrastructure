/**
 * Cola SQS de los cuatro eventos de ciclo de vida de Producto (ADR-018,
 * Accepted en Management #314):
 *
 *  - catalog.product.suspended
 *  - catalog.product.reactivated
 *  - catalog.product.inventory.adjusted
 *  - catalog.product.premium.configured
 *
 * Modulo DELIBERADAMENTE SEPARADO de infra/modules/catalog_events_queue
 * (ADR-017, catalog.product.created), no una parametrizacion de aquel.
 * Management#314 condiciono la aprobacion a no modificar ni arriesgar la cola
 * de `catalog.product.created` ya en produccion de codigo: reutilizar ese
 * modulo con un `for_each`/`count` habria cambiado las direcciones de sus
 * recursos (`aws_sqs_queue.main` -> `aws_sqs_queue.main["created"]`), lo que
 * un `terraform plan` real interpreta como destruir y recrear el recurso
 * existente. Un modulo nuevo, aunque duplique estructura, es la unica forma
 * de anadir esta cola sin arriesgar esa condicion.
 *
 * Comparte topologia y parametros con infra/modules/catalog_events_queue
 * porque ADR-018 adopta exactamente los mismos valores que ADR-017 aprobo
 * para `created`, no porque el codigo dependa de aquel modulo.
 */

locals {
  main_queue_name = "nexus-battle-${var.environment}-catalog-lifecycle-notifications"
  dlq_name        = "${local.main_queue_name}-dlq"

  common_tags = merge(var.tags, {
    Component = "catalog-lifecycle-events"
    EventTypes = join(",", [
      "catalog.product.suspended",
      "catalog.product.reactivated",
      "catalog.product.inventory.adjusted",
      "catalog.product.premium.configured",
    ])
    Adr = "ADR-018"
  })
}

resource "aws_sqs_queue" "dlq" {
  name = local.dlq_name

  # 14 dias, mismo valor aprobado en ADR-018 (identico a ADR-017). Mayor que
  # la retencion de la cola principal para que un mensaje redirigido no
  # caduque antes de que alguien lo revise.
  message_retention_seconds = 1209600

  # SSE-SQS con clave administrada por SQS. Igual que ADR-017: sin KMS de
  # cliente, fuera del techo de coste aprobado.
  sqs_managed_sse_enabled = true

  tags = local.common_tags
}

resource "aws_sqs_queue" "main" {
  name = local.main_queue_name

  # SQS Standard, no FIFO: misma decision que ADR-017, por el mismo motivo -el
  # orden y la deduplicacion del broker no eliminan la necesidad de
  # idempotencia por eventId, y FIFO cuesta mas sin necesidad-.
  fifo_queue = false

  receive_wait_time_seconds  = 20
  visibility_timeout_seconds = 60

  # 4 dias, igual que ADR-017.
  message_retention_seconds = 345600

  # Limite CONTRACTUAL ya existente para eventos de Catalog (mismo binding
  # `x-aws-sqs` del AsyncAPI que usa `catalog.product.created`), aunque SQS
  # admita payloads mayores.
  max_message_size = 65536

  sqs_managed_sse_enabled = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = local.common_tags
}

# La DLQ solo permite redrive desde esta cola: sin esta politica,
# `redrivePermission` por defecto es `allowAll` y cualquier cola de la cuenta
# -incluida la de `catalog.product.created`- podria redirigir hacia esta DLQ,
# mezclando dominios de mensajes que Management#314 exigio mantener separados.
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.main.arn]
  })
}

/**
 * Sin principal publico, mismo criterio que infra/modules/catalog_events_queue:
 * una cola SQS no es alcanzable sin una politica que lo permita
 * explicitamente, pero se declara la denegacion de trafico sin TLS de forma
 * explicita en vez de confiar en que HTTPS+SigV4 sea siempre lo que use cada
 * cliente.
 */
data "aws_iam_policy_document" "solo_tls" {
  for_each = { main = aws_sqs_queue.main.arn, dlq = aws_sqs_queue.dlq.arn }

  statement {
    sid    = "DenegarSinTLS"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["sqs:*"]
    resources = [each.value]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "main" {
  queue_url = aws_sqs_queue.main.id
  policy    = data.aws_iam_policy_document.solo_tls["main"].json
}

resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  policy    = data.aws_iam_policy_document.solo_tls["dlq"].json
}

# Alarmas minimas, mismo patron aprobado en ADR-017/ADR-018. No se anaden mas:
# el coste debe quedarse dentro de la estimacion de
# docs/costs/catalog-lifecycle-sqs-estimate.md.
resource "aws_cloudwatch_metric_alarm" "age_of_oldest_message" {
  alarm_name        = "${local.main_queue_name}-age-oldest-message"
  alarm_description = "Mensaje mas antiguo de la cola de eventos de ciclo de vida de Producto supera el umbral (ADR-018)."

  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = var.max_age_oldest_message_alarm_seconds

  dimensions = {
    QueueName = aws_sqs_queue.main.name
  }

  alarm_actions = var.alarm_actions
  tags          = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "dlq_messages_visible" {
  alarm_name        = "${local.dlq_name}-messages-visible"
  alarm_description = "La DLQ de eventos de ciclo de vida de Producto tiene al menos un mensaje (ADR-018)."

  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }

  alarm_actions = var.alarm_actions
  tags          = local.common_tags
}
