output "lb_ip" {
  value = google_compute_global_address.lb_ip.address
}

output "frontend_url" {
  value = "http://${google_compute_global_address.lb_ip.address}"
}
