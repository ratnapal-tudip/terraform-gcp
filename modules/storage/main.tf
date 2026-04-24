###############################################################
# MODULE: CLOUD STORAGE
# - GCS bucket for React frontend static files
# - Public read access (website hosting)
# - CORS configured
###############################################################

resource "google_storage_bucket" "frontend" {
  project                     = var.project_id
  name                        = "${var.project_id}-react-frontend"
  location                    = "US" # multi-region = free egress within US
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy               = true

  website {
    main_page_suffix = "index.html"
    not_found_page   = "index.html" # SPA routing — always serve index.html
  }

  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "OPTIONS"]
    response_header = ["Content-Type", "Cache-Control"]
    max_age_seconds = 3600
  }

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type = "Delete"
    }
  }
}

# ── Make bucket publicly readable ─────────────────────────────
resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.frontend.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}
