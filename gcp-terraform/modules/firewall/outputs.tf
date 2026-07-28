output "internal_rule_name" {
  description = "Name of the allow-internal firewall rule."
  value       = google_compute_firewall.internal.name
}

output "iap_ssh_rule_name" {
  description = "Name of the IAP-SSH firewall rule (target tag: iap-ssh)."
  value       = google_compute_firewall.iap_ssh.name
}

output "health_check_rule_name" {
  description = "Name of the health-check firewall rule."
  value       = google_compute_firewall.health_checks.name
}
