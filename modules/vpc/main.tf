###############################################################
# MODULE: VPC
# - Custom VPC
# - Private Subnet (backend VM)
# - Public Subnet  (Jenkins VM)
# - Cloud Router + Cloud NAT (outbound traffic for private subnet)
# - Firewall rules
###############################################################

# ── VPC ──────────────────────────────────────────────────────
resource "google_compute_network" "vpc" {
  project                 = var.project_id
  name                    = "ratnapal-vpc"
  auto_create_subnetworks = false
  description             = "Main VPC for Ratnapal project"
}

# ── PRIVATE SUBNET (Backend VM) ──────────────────────────────
resource "google_compute_subnetwork" "private_subnet" {
  project                  = var.project_id
  name                     = "private-subnet"
  ip_cidr_range            = "10.0.1.0/24"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true # allows VM to reach GCP APIs without public IP
}

# ── PUBLIC SUBNET (Jenkins VM) ────────────────────────────────
resource "google_compute_subnetwork" "public_subnet" {
  project       = var.project_id
  name          = "public-subnet"
  ip_cidr_range = "10.0.2.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

# ── CLOUD ROUTER ──────────────────────────────────────────────
resource "google_compute_router" "router" {
  project = var.project_id
  name    = "ratnapal-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

# ── CLOUD NAT (outbound internet for private subnet) ──────────
resource "google_compute_router_nat" "nat" {
  project                            = var.project_id
  name                               = "ratnapal-cloud-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.private_subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

# ── FIREWALL: Allow internal VPC traffic ──────────────────────
resource "google_compute_firewall" "allow_internal" {
  project = var.project_id
  name    = "allow-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.0.0/16"]
  description   = "Allow all traffic within VPC"
}

# ── FIREWALL: Allow HTTP/HTTPS from Load Balancer ────────────
resource "google_compute_firewall" "allow_http_https" {
  project = var.project_id
  name    = "allow-http-https"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8000", "8001", "8002", "8003"]
  }

  # GCP Load Balancer health check IPs
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["backend-vm"]
  description   = "Allow LB health checks and traffic to backend VM"
}

# ── FIREWALL: Allow SSH + Jenkins UI from anywhere (0.0.0.0/0) ─
resource "google_compute_firewall" "allow_jenkins_access" {
  project = var.project_id
  name    = "allow-jenkins-access"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22", "8080"]
  }

  source_ranges = ["0.0.0.0/0"] # restrict to your IP later
  target_tags   = ["jenkins-vm"]
  description   = "SSH and Jenkins UI access - restrict source IP in production"
}

# ── FIREWALL: Allow health checks ────────────────────────────
resource "google_compute_firewall" "allow_health_check" {
  project = var.project_id
  name    = "allow-health-check"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  description   = "GCP health check probes"
}
