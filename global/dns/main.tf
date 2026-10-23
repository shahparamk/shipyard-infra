variable "domain_name" {
  description = "Domain registered at the registrar and delegated to Route 53"
  type        = string
  default     = "paramshah.tech"
}

resource "aws_route53_zone" "this" {
  #checkov:skip=CKV2_AWS_38:DNSSEC needs a KMS key plus a DS record at the registrar; deferred for a portfolio domain
  #checkov:skip=CKV2_AWS_39:Query logging adds CloudWatch cost with little value for a low-traffic portfolio domain
  name    = var.domain_name
  comment = "ShipYard public DNS (records managed by Terraform and ExternalDNS)"
}

output "zone_id" {
  value = aws_route53_zone.this.zone_id
}

output "name_servers" {
  description = "Paste these 4 into the registrar as custom nameservers"
  value       = aws_route53_zone.this.name_servers
}