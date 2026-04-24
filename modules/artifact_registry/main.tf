###############################################################
# MODULE: ARTIFACT REGISTRY
# - Docker repository for storing container images
# - Jenkins pushes here, backend VM pulls from here
###############################################################

resource "google_artifact_registry_repository" "docker_repo" {
  project       = var.project_id
  location      = var.region
  repository_id = "ratnapal-images"
  description   = "Docker images for Ratnapal backend services"
  format        = "DOCKER"

  cleanup_policy_dry_run = false

  # Keep only last 5 versions per image to save storage cost
  cleanup_policies {
    id     = "keep-5-versions"
    action = "KEEP"
    most_recent_versions {
      keep_count = 5
    }
  }
}
