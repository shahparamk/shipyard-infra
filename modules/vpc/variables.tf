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

variable "az_count" {
  description = "How many availability zones to spread subnets across"
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3 (EKS needs at least 2 AZs)."
  }
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