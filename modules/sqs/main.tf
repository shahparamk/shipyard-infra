# Dead-letter queue: poison messages land here instead of retrying forever
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name}-dlq"
  message_retention_seconds = 1209600 # 14 days to inspect failures
  sqs_managed_sse_enabled   = true
  tags                      = var.tags
}

resource "aws_sqs_queue" "this" {
  name                       = var.name
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = 345600 # 4 days
  receive_wait_time_seconds  = 20     # long polling by default
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = var.tags
}

# Only the main queue may send messages to this DLQ
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.this.arn]
  })
}

# Deny any non-TLS access to both queues
locals {
  queues = {
    main = { url = aws_sqs_queue.this.id, arn = aws_sqs_queue.this.arn }
    dlq  = { url = aws_sqs_queue.dlq.id, arn = aws_sqs_queue.dlq.arn }
  }
}

data "aws_iam_policy_document" "tls_only" {
  for_each = local.queues

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [each.value.arn]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "tls_only" {
  for_each = local.queues

  queue_url = each.value.url
  policy    = data.aws_iam_policy_document.tls_only[each.key].json
}