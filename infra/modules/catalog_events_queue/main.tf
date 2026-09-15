/**
 * Cola SQS de `catalog.product.created` (ADR-017, Accepted en EN-027.4 #284,
 * merge de Infrastructure #65).
 *
 * Provisiona UNICAMENTE lo que ADR-017 aprobo: una cola Standard punto a
 * punto para este evento y su DLQ. NO incluye:
 *
 *  - dispatcher/worker de Catalog (auditado y confirmado ausente en su
 *    codigo: es un PR separado en Nexus-Battle-Catalog);
 *  - colas para catalog.product.suspended/reactivated/inventory.adjusted/
 *    premium.configured (los eventos de ciclo de vida): ADR-017 cubre
 *    explicitamente solo `created`; los demas siguen BLOCKED BY ARCHITECTURE
 *    DECISION hasta que exista una extension de ADR-017 o un ADR nuevo.
 *
 * Aceptar el ADR no equivale a desplegar: este modulo es la primera pieza que
 * lo convierte en infraestructura real, pero el flujo completo sigue
 * incompleto mientras falte el dispatcher de Catalog.
 */

locals {
  main_queue_name = "nexus-battle-${var.environment}-catalog-product-created-notifications"
  dlq_name        = "${local.main_queue_name}-dlq"

  common_tags = merge(var.tags, {
    Component = "catalog-events"
    Event     = "catalog.product.created"
    Adr       = "ADR-017"
  })
}

resource "aws_sqs_queue" "dlq" {
  name = local.dlq_name

  # 14 dias, valor aprobado en ADR-017. Debe ser mayor que la retencion de la
  # cola principal para que un mensaje redirigido no caduque antes de que
  # alguien lo revise.
  message_retention_seconds = 1209600

  # SSE-SQS con clave administrada por SQS. ADR-017 descarta explicitamente
  # KMS de cliente para no introducir un coste que la estimacion aprobada no
  # contempla.
  sqs_managed_sse_enabled = true

  tags = local.common_tags
}

resource "aws_sqs_queue" "main" {
  name = local.main_queue_name

  # SQS Standard, no FIFO: ADR-017 rechazo FIFO porque el orden y la
  # deduplicacion del broker no eliminan la necesidad de idempotencia extremo
  # a extremo (por `eventId`), y FIFO cuesta mas sin necesidad para `created`.
  fifo_queue = false

  # Long polling: reduce las llamadas vacias frente a short polling, que es
  # buena parte del coste estimado en ADR-017.
  receive_wait_time_seconds = 20

  # El handler debe terminar antes de este plazo o extender la visibilidad
  # explicitamente; si no, SQS vuelve a entregar el mensaje a otro consumidor.
  visibility_timeout_seconds = 60

  # 4 dias, valor aprobado en ADR-017.
  message_retention_seconds = 345600

  # Limite CONTRACTUAL de ADR-017 y del binding `x-aws-sqs` del AsyncAPI
  # (`catalog-events-v1.asyncapi.yaml`), aunque SQS admita payloads mayores.
  max_message_size = 65536

  sqs_managed_sse_enabled = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = local.common_tags
}

# La DLQ solo permite redrive desde la cola fuente definida (ADR-017,
# seccion 5): sin esta politica, `redrivePermission` por defecto es
# `allowAll` y cualquier cola de la cuenta podria redirigir hacia esta DLQ.
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.main.arn]
  })
}

/**
 * Sin principal publico (ADR-017, seccion 7).
 *
 * Por defecto una cola SQS ya no es alcanzable sin una politica que lo
 * permita explicitamente -a diferencia de S3, aqui no existe una superficie
 * publica que cerrar-, pero se declara la denegacion de trafico sin TLS de
 * forma explicita, igual que en `product_assets` (`solo_tls`), en vez de
 * confiar en que HTTPS+SigV4 sea siempre lo que use cada cliente.
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

# Alarmas minimas aprobadas por ADR-017 (seccion 8). No se anaden mas: el
# coste debe quedarse dentro de la estimacion aceptada en Management #284.
resource "aws_cloudwatch_metric_alarm" "age_of_oldest_message" {
  alarm_name        = "${local.main_queue_name}-age-oldest-message"
  alarm_description = "Mensaje mas antiguo de la cola de catalog.product.created supera el umbral (ADR-017)."

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
  alarm_description = "La DLQ de catalog.product.created tiene al menos un mensaje (ADR-017)."

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
