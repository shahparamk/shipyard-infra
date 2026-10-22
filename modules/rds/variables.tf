variable "name" {
  description = "DB instance identifier"
  type        = string
}

variable "engine_version" {
  description = "Postgres version; check with: aws rds describe-db-engine-versions --engine postgres --default-only"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnets for the DB subnet group"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to connect on 5432 (the EKS cluster SG)"
  type        = list(string)
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "GiB"
  type        = number
  default     = 20
}

variable "db_name" {
  type    = string
  default = "orders"
}

variable "username" {
  type    = string
  default = "shipyard"
}

variable "log_retention_days" {
  type    = number
  default = 7
}

variable "tags" {
  type    = map(string)
  default = {}
}