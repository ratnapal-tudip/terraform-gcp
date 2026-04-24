output "backend_instance_group" {
  value = google_compute_instance_group.backend_group.id
}

output "jenkins_public_ip" {
  value = google_compute_instance.jenkins_vm.network_interface[0].access_config[0].nat_ip
}

output "backend_private_ip" {
  value = google_compute_instance.backend_vm.network_interface[0].network_ip
}

output "backend_vm_self_link" {
  value = google_compute_instance.backend_vm.self_link
}
