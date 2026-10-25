# Free TLS certificate for the public site, validated by a DNS record in our own zone
resource "aws_acm_certificate" "shipyard" {
  domain_name       = "shipyard.${var.domain_name}"
  validation_method = "DNS"

  # Create the replacement before deleting the old one, so HTTPS never goes down
  lifecycle {
    create_before_destroy = true
  }
}

# The record ACM checks to prove we control the domain
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.shipyard.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = aws_route53_zone.this.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# Waits until ACM sees the record and issues the certificate
resource "aws_acm_certificate_validation" "shipyard" {
  certificate_arn         = aws_acm_certificate.shipyard.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

output "shipyard_certificate_arn" {
  value = aws_acm_certificate_validation.shipyard.certificate_arn
}