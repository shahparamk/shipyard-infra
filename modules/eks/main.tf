# ---------------- Cluster IAM role ----------------

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------------- Control-plane logs ----------------

# Created before the cluster so we control retention (EKS would otherwise create it with "never expire")
resource "aws_cloudwatch_log_group" "cluster" {
  #checkov:skip=CKV_AWS_158:Control-plane logs are encrypted at rest by CloudWatch by default; a dedicated KMS key isn't justified for dev
  #checkov:skip=CKV_AWS_338:Short retention is a deliberate dev cost control; raise for prod/compliance

  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_days
  tags              = var.tags
}

# ---------------- Cluster ----------------

resource "aws_eks_cluster" "this" {
  #checkov:skip=CKV_AWS_38:Public endpoint is open so I can reach the API from changing networks; every request still requires IAM auth via access entries. Prod would use a private endpoint + VPN/bastion
  #checkov:skip=CKV_AWS_39:Same as CKV_AWS_38; private access is also enabled so nodes talk to the API inside the VPC
  #checkov:skip=CKV_AWS_58:EKS encrypts Kubernetes API data (including Secrets) at rest by default with envelope encryption; a customer-managed KMS key adds cost per short-lived dev cluster
  #checkov:skip=CKV_AWS_339:Version is AWS's current default from describe-cluster-versions (1.37, STANDARD_SUPPORT); Checkov's built-in version list lags new EKS releases. upgrade_policy pins STANDARD support
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
  }

  # Access entries only (no aws-auth ConfigMap); the creator (CI role) gets NO automatic admin
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  # Guard against silently moving to extended support ($0.60/hr instead of $0.10/hr)
  upgrade_policy {
    support_type = "STANDARD"
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_cloudwatch_log_group.cluster,
  ]
}

# ---------------- Node IAM role ----------------

data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",          # join the cluster
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",               # assign pod IPs (move to Pod Identity later)
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly", # pull images from ECR
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",       # shell access via SSM, no SSH keys or open ports
  ])

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# ---------------- Managed node group ----------------

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = var.node_capacity_type
  instance_types = var.node_instance_types
  disk_size      = var.node_disk_size

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = "general"
  }

  tags = var.tags

  # Autoscalers will change the node count later; don't let Terraform fight them
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}

# ---------------- Managed add-ons ----------------

resource "aws_eks_addon" "this" {
  for_each = toset(["vpc-cni", "kube-proxy", "coredns", "eks-pod-identity-agent"])

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.value
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags

  # coredns needs nodes to schedule onto
  depends_on = [aws_eks_node_group.default]
}

# ---------------- Access: who can use kubectl ----------------

resource "aws_eks_access_entry" "admins" {
  for_each = toset(var.admin_role_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"
  tags          = var.tags
}

resource "aws_eks_access_policy_association" "admins" {
  for_each = toset(var.admin_role_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admins]
}