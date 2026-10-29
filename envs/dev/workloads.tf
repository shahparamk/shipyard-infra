# Each workload gets its own IAM role, tied to one Kubernetes namespace + service account.
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

# ---------------- Bind app roles to service accounts (only while the cluster exists) ----------------

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

# ---------------- External Secrets: may only READ shipyard/dev/* secrets ----------------

resource "aws_iam_role" "external_secrets" {
  name               = "${local.name}-external-secrets"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

data "aws_iam_policy_document" "external_secrets" {
  statement {
    actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    # Secrets Manager adds a random 6-character suffix to ARNs, hence the trailing wildcard
    resources = ["arn:aws:secretsmanager:us-east-1:${data.aws_caller_identity.current.account_id}:secret:shipyard/dev/*"]
  }
}

resource "aws_iam_role_policy" "external_secrets" {
  name   = "read-dev-secrets"
  role   = aws_iam_role.external_secrets.id
  policy = data.aws_iam_policy_document.external_secrets.json
}

resource "aws_eks_pod_identity_association" "external_secrets" {
  count = local.cluster_enabled ? 1 : 0

  cluster_name    = module.eks[0].cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.external_secrets.arn
}

# ---------------- AWS Load Balancer Controller: builds ALBs from Ingresses ----------------

resource "aws_iam_role" "aws_load_balancer_controller" {
  name               = "${local.name}-aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

# Official upstream policy for controller v3.6.0, vendored so changes show up in PRs
resource "aws_iam_policy" "aws_load_balancer_controller" {
  name        = "${local.name}-aws-load-balancer-controller"
  description = "Official AWS Load Balancer Controller policy (v3.6.0), vendored from upstream"
  policy      = file("${path.module}/policies/aws-load-balancer-controller.json")
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  role       = aws_iam_role.aws_load_balancer_controller.name
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
}

resource "aws_eks_pod_identity_association" "aws_load_balancer_controller" {
  count = local.cluster_enabled ? 1 : 0

  cluster_name    = module.eks[0].cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.aws_load_balancer_controller.arn
}

# ---------------- ExternalDNS: may only manage records in OUR hosted zone ----------------

data "aws_route53_zone" "public" {
  name = "paramshah.tech"
}

resource "aws_iam_role" "external_dns" {
  name               = "${local.name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

data "aws_iam_policy_document" "external_dns" {
  # Write + read records: only this one zone
  statement {
    sid = "ManageRecordsInOurZone"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResources",
    ]
    resources = ["arn:aws:route53:::hostedzone/${data.aws_route53_zone.public.zone_id}"]
  }

  # Zone discovery: ListHostedZones can't be scoped to a single zone, so AWS requires "*"
  statement {
    sid       = "DiscoverZones"
    actions   = ["route53:ListHostedZones"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "external_dns" {
  name   = "manage-public-zone-records"
  role   = aws_iam_role.external_dns.id
  policy = data.aws_iam_policy_document.external_dns.json
}

resource "aws_eks_pod_identity_association" "external_dns" {
  count = local.cluster_enabled ? 1 : 0

  cluster_name    = module.eks[0].cluster_name
  namespace       = "external-dns"
  service_account = "external-dns"
  role_arn        = aws_iam_role.external_dns.arn
}

# ---------------- KEDA: may only READ the orders queue's depth ----------------

resource "aws_iam_role" "keda_operator" {
  name               = "${local.name}-keda-operator"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

data "aws_iam_policy_document" "keda_operator" {
  # Read-only: how many messages are waiting / in flight. KEDA can't send, receive, or delete.
  statement {
    actions   = ["sqs:GetQueueAttributes"]
    resources = [module.orders_queue.queue_arn]
  }
}

resource "aws_iam_role_policy" "keda_operator" {
  name   = "read-orders-queue-depth"
  role   = aws_iam_role.keda_operator.id
  policy = data.aws_iam_policy_document.keda_operator.json
}

