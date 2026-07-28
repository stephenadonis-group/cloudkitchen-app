output "instance_name" {
  description = "Bastion VM name."
  value       = google_compute_instance.bastion.name
}

output "instance_zone" {
  description = "Bastion VM zone."
  value       = google_compute_instance.bastion.zone
}

output "internal_ip" {
  description = "Bastion's internal IP (no public IP exists)."
  value       = google_compute_instance.bastion.network_interface[0].network_ip
}
