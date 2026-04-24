###############################################################
# ROOT OUTPUTS
###############################################################

output "load_balancer_ip" {
  description = "Public IP of the HTTP Load Balancer"
  value       = module.load_balancer.lb_ip
}

output "jenkins_vm_ip" {
  description = "Public IP of the Jenkins VM (access :8080 for Jenkins UI)"
  value       = module.compute.jenkins_public_ip
}

output "backend_vm_private_ip" {
  description = "Private IP of the Backend VM"
  value       = module.compute.backend_private_ip
}

output "artifact_registry_url" {
  description = "Docker registry URL for pushing images"
  value       = module.artifact_registry.registry_url
}

output "frontend_bucket_url" {
  description = "GCS bucket URL for React frontend"
  value       = module.storage.bucket_url
}

output "cloud_sql_private_ip" {
  description = "Private IP of MySQL Cloud SQL instance"
  value       = module.sql.sql_private_ip
}

output "frontend_public_url" {
  description = "Public URL to access React frontend via CDN"
  value       = module.load_balancer.frontend_url
}
