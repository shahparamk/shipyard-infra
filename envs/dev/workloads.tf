# Each app gets its own IAM role, tied to one Kubernetes namespace + service account.
locals {
  app_namespace = "shipyard"
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# ---------------- API: may only SEND orders ----------------

resource "aws_iam_role" "orders_api" {
  name               = "${local.name}-orders-api"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

data "aws_iam_policy_document" "orders_api" {
  statement {
    actions   = ["sqs:SendMessage"]
    resources = [module.orders_queue.queue_arn]
  }
}

resource "aws_iam_role_policy" "orders_api" {
  name   = "send-orders"
  role   = aws_iam_role.orders_api.id
  policy = data.aws_iam_policy_document.orders_api.json
}

# ---------------- Worker: may only RECEIVE/DELETE orders ----------------

resource "aws_iam_role" "orders_worker" {
  name               = "${local.name}-orders-worker"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

data "aws_iam_policy_document" "orders_worker" {
  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueAttributes",
    ]
    resources = [module.orders_queue.queue_arn]
  }
}

resource "aws_iam_role_policy" "orders_worker" {
  name   = "consume-orders"
  role   = aws_iam_role.orders_worker.id
  policy = data.aws_iam_policy_document.orders_worker.json
}

# ---------------- Bind roles to service accounts (only while the cluster exists) ----------------

resource "aws_eks_pod_identity_association" "orders_api" {
  count = local.cluster_enabled ? 1 : 0

  cluster_name    = module.eks[0].cluster_name
  namespace       = local.app_namespace
  service_account = "orders-api"
  role_arn        = aws_iam_role.orders_api.arn
}

resource "aws_eks_pod_identity_association" "orders_worker" {
  count = local.cluster_enabled ? 1 : 0

  cluster_name    = module.eks[0].cluster_name
  namespace       = local.app_namespace
  service_account = "orders-worker"
  role_arn        = aws_iam_role.orders_worker.arn
}