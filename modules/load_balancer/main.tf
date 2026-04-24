###############################################################
# MODULE: LOAD BALANCER + CDN
# - Global HTTP Load Balancer (Layer 7)
# - Cloud CDN for frontend (GCS bucket)
# - Backend service pointing to backend VM instance group
# - URL map: /api/* → backend VM, /* → GCS bucket (React)
###############################################################

# ── Global Static IP ──────────────────────────────────────────
resource "google_compute_global_address" "lb_ip" {
  project = var.project_id
  name    = "ratnapal-lb-ip"
}

# ── Backend Bucket (React Frontend + CDN) ─────────────────────
resource "google_compute_backend_bucket" "frontend_backend" {
  project     = var.project_id
  name        = "frontend-backend-bucket"
  bucket_name = var.frontend_bucket
  enable_cdn  = true

  cdn_policy {
    cache_mode        = "CACHE_ALL_STATIC"
    client_ttl        = 3600
    default_ttl       = 3600
    max_ttl           = 86400
    serve_while_stale = 86400
  }
}

# ── Health Check for Backend VM ───────────────────────────────
resource "google_compute_health_check" "backend_health" {
  project             = var.project_id
  name                = "backend-vm-health-check"
  check_interval_sec  = 30
  timeout_sec         = 10
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 80
    request_path = "/health"
  }
}

# ── Backend Service (pointing to VM instance group) ───────────
resource "google_compute_backend_service" "backend_service" {
  project               = var.project_id
  name                  = "backend-vm-service"
  protocol              = "HTTP"
  port_name             = "fastapi"
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 30
  health_checks         = [google_compute_health_check.backend_health.id]

  backend {
    group           = var.backend_vm_group
    balancing_mode  = "UTILIZATION"
    max_utilization = 0.8
  }

  log_config {
    enable      = true
    sample_rate = 0.5
  }
}

# ── URL Map ───────────────────────────────────────────────────
# /api/fastapi/* → FastAPI (port 8000)
# /api/django/*  → Django  (port 8001)
# /api/node/*    → Node    (port 8002)
# /api/dotnet/*  → .Net    (port 8003)
# /*             → React frontend (GCS bucket via CDN)
resource "google_compute_url_map" "url_map" {
  project         = var.project_id
  name            = "ratnapal-url-map"
  default_service = google_compute_backend_bucket.frontend_backend.id

  host_rule {
    hosts        = ["*"]
    path_matcher = "allpaths"
  }

  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_bucket.frontend_backend.id

    path_rule {
      paths   = ["/api/*", "/api"]
      service = google_compute_backend_service.backend_service.id
    }
  }
}

# ── HTTP Target Proxy ─────────────────────────────────────────
resource "google_compute_target_http_proxy" "http_proxy" {
  project = var.project_id
  name    = "ratnapal-http-proxy"
  url_map = google_compute_url_map.url_map.id
}

# ── Global Forwarding Rule (HTTP :80) ─────────────────────────
resource "google_compute_global_forwarding_rule" "http_rule" {
  project               = var.project_id
  name                  = "ratnapal-http-forwarding-rule"
  load_balancing_scheme = "EXTERNAL"
  ip_address            = google_compute_global_address.lb_ip.address
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.http_proxy.id
}
