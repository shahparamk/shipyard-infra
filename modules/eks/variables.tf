variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version; check with: aws eks describe-cluster-versions --default-only"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the control-plane ENIs and worker nodes"
  type        = list(string)
}

variable "admin_role_arns" {
  description = "IAM role ARNs that get cluster-admin through EKS access entries"
  type        = list(string)
  default     = []
}

variable "node_instance_types" {
  description = "Several similar types improve spot availability"
  type        = list(string)
  default     = ["t3.medium", "t3a.medium"]
}

variable "node_capacity_type" {
  description = "SPOT (cheaper, can be interrupted) or ON_DEMAND"
  type        = string
  default     = "SPOT"

  validation {
    condition     = contains(["SPOT", "ON_DEMAND"], var.node_capacity_type)
    error_message = "node_capacity_type must be SPOT or ON_DEMAND."
  }
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "node_disk_size" {
  description = "Root volume size in GiB"
  type        = number
  default     = 20
}

variable "cluster_log_retention_days" {
  type    = number
  default = 7
}

variable "tags" {
  type    = map(string)
  default = {}
}