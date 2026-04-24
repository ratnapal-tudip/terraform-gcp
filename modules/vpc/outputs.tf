output "vpc_name"          { value = google_compute_network.vpc.name }
output "vpc_self_link"     { value = google_compute_network.vpc.self_link }
output "private_subnet_id" { value = google_compute_subnetwork.private_subnet.id }
output "public_subnet_id"  { value = google_compute_subnetwork.public_subnet.id }
