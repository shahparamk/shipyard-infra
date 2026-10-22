variable "name" {
  description = "Queue name; the DLQ is <name>-dlq"
  type        = string
}

variable "visibility_timeout_seconds" {
  description = "How long a received message stays hidden from other consumers"
  type        = number
  default     = 30
}

variable "max_receive_count" {
  description = "Failed receives before a message moves to the DLQ"
  type        = number
  default     = 5
}

variable "tags" {
  type    = map(string)
  default = {}
}