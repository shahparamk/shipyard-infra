variable "name" {
  description = "Name prefix for all VPC resources, e.g. shipyard-dev"
  type        = string
}

variable "cidr_block" {
  description = "CIDR range for the whole VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid CIDR, e.g. 10.0.0.0/16."
  }
}

variable "azs" {
  description = "Availability zones to use, pinned explicitly so subnets never shift if AWS adds or reorders zones"
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 3
    error_message = "Provide 2 or 3 AZs (EKS needs at least 2)."
  }
}

variable "enable_flow_logs" {
  description = "Send VPC flow logs to CloudWatch Logs"
  type        = bool
  default     = true
}

variable "flow_log_traffic_type" {
  description = "REJECT (cheapest, shows blocked traffic), ACCEPT, or ALL"
  type        = string
  default     = "REJECT"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_log_traffic_type)
    error_message = "flow_log_traffic_type must be ACCEPT, REJECT, or ALL."
  }
}

variable "flow_log_retention_days" {
  description = "How long CloudWatch keeps flow logs"
  type        = number
  default     = 7
}

variable "enable_nat_gateway" {
  description = "Create a single NAT gateway so private subnets can reach the internet (costs ~$33/month)"
  type        = bool
  default     = false
}

variable "cluster_name" {
  description = "EKS cluster name, used in subnet tags so Kubernetes controllers can discover subnets"
  type        = string
}

variable "tags" {
  description = "Extra tags for all resources"
  type        = map(string)
  default     = {}
}