locals {
  main_queue_name = "nexus-battle-${var.environment}-auction-settlement-notifications"
  dlq_name        = "${local.main_queue_name}-dlq"
  tags = merge(var.tags, {
    Component = "auction-settlement-notifications"
    Event     = "auction.settled.v1"
  })
}

resource "aws_sqs_queue" "dlq" {
  name                      = local.dlq_name
  fifo_queue                = false
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
  tags                      = local.tags
}
resource "aws_sqs_queue" "main" {
  name                       = local.main_queue_name
  fifo_queue                 = false
  receive_wait_time_seconds  = 20
  visibility_timeout_seconds = 60
  message_retention_seconds  = 345600
  sqs_managed_sse_enabled    = true
  redrive_policy             = jsonencode({ deadLetterTargetArn = aws_sqs_queue.dlq.arn, maxReceiveCount = 5 })
  tags                       = local.tags
}
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url            = aws_sqs_queue.dlq.id
  redrive_allow_policy = jsonencode({ redrivePermission = "byQueue", sourceQueueArns = [aws_sqs_queue.main.arn] })
}
data "aws_iam_policy_document" "deny_insecure_transport" {
  for_each = { main = aws_sqs_queue.main.arn, dlq = aws_sqs_queue.dlq.arn }
  statement {
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
  policy    = data.aws_iam_policy_document.deny_insecure_transport["main"].json
}

resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  policy    = data.aws_iam_policy_document.deny_insecure_transport["dlq"].json
}
