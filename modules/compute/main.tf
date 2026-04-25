###############################################################
# MODULE: COMPUTE
# - Service Account for VMs
# - Backend VM (private subnet) — runs 4 Docker containers
# - Jenkins VM (public subnet)  — CI/CD pipeline
# - Unmanaged Instance Groups for Load Balancer
###############################################################

# ── SERVICE ACCOUNT for VMs ───────────────────────────────────
resource "google_service_account" "vm_sa" {
  project      = var.project_id
  account_id   = "ratnapal-vm-sa"
  display_name = "Ratnapal VM Service Account"
}

# Grant Artifact Registry reader on backend, writer on Jenkins
resource "google_project_iam_member" "sa_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.vm_sa.email}"
}

resource "google_project_iam_member" "sa_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.vm_sa.email}"
}

resource "google_project_iam_member" "sa_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.vm_sa.email}"
}

resource "google_project_iam_member" "sa_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.vm_sa.email}"
}

resource "google_project_iam_member" "sa_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.vm_sa.email}"
}

resource "google_project_iam_member" "sa_network_viewer" {
  project = var.project_id
  role    = "roles/compute.networkViewer"
  member  = "serviceAccount:${google_service_account.vm_sa.email}"
}

# ── BACKEND VM (Private Subnet) ───────────────────────────────
# e2-micro = free tier eligible (1 vCPU, 1GB RAM)
resource "google_compute_instance" "backend_vm" {
  project      = var.project_id
  name         = "backend-vm"
  machine_type = "e2-medium" # 4GB RAM
  zone         = var.zone
  tags         = ["backend-vm"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 30   # 30 GB — free tier gives 30 GB standard persistent disk
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = var.private_subnet_id
    # No access_config = no public IP (private only, outbound via NAT)
  }

  service_account {
    email  = google_service_account.vm_sa.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  # Startup script: install Docker, configure auth, pull & run containers
  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -e

    # ── Install Docker ──────────────────────────────────────
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    ARCH=$(dpkg --print-architecture)
    CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
    echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # ── Install gcloud CLI ────────────────────────────────────
    apt-get update && apt-get install -y ca-certificates gnupg curl
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
    apt-get update -y && apt-get install -y google-cloud-cli

    # ── Authenticate Docker with Artifact Registry ──────────
    gcloud auth configure-docker ${var.region}-docker.pkg.dev --quiet

    echo "Backend VM ready. Jenkins will deploy containers via docker-compose."
    echo "Artifact Registry: ${var.artifact_registry_repo}"
  EOT

  description = "Backend VM running 4 Docker containers in private subnet"
}

# ── JENKINS VM (Public Subnet) ────────────────────────────────
# e2-micro — Jenkins can run on it for small workloads
resource "google_compute_instance" "jenkins_vm" {
  project      = var.project_id
  name         = "jenkins-vm"
  machine_type = "e2-medium" # e2-medium for Jenkins (2 vCPU, 4GB) — minimal cost
  zone         = var.zone
  tags         = ["jenkins-vm"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 30
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = var.public_subnet_id
    access_config {
      # Ephemeral public IP for Jenkins
    }
  }

  service_account {
    email  = google_service_account.vm_sa.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  # Startup script: install Docker, Jenkins via docker-compose, gcloud
  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -e

    # ── System update ────────────────────────────────────────
    apt-get update -y
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release git wget

    # ── Install Docker ────────────────────────────────────────
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    ARCH=$(dpkg --print-architecture)
    CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
    echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable docker
    systemctl start docker

    # ── Install gcloud CLI ────────────────────────────────────
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
    apt-get update -y
    apt-get install -y google-cloud-cli

    # Configure Docker auth for Artifact Registry
    gcloud auth configure-docker ${var.region}-docker.pkg.dev --quiet

    # ── Setup Jenkins via Docker ───────────────────────────────
    mkdir -p /opt/jenkins
    cd /opt/jenkins

    # Give Jenkins container permission to talk to Docker socket
    chmod 666 /var/run/docker.sock

    cat << 'EOF' > Dockerfile
FROM jenkins/jenkins:lts

USER root

RUN apt-get update && \
    apt-get install -y ca-certificates curl gnupg && \
    # Add Docker official GPG key
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    # Add Docker repo
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/debian \
      bookworm stable" \
      > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    # Install everything properly
    apt-get install -y \
      docker-ce-cli \
      docker-buildx-plugin \
      docker-compose-plugin && \
    # Install GCP CLI
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
    apt-get update && apt-get install -y google-cloud-cli && \
    apt-get clean

# Install Node.js v20
RUN apt-get update && \
    apt-get install -y curl ca-certificates gnupg && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs

USER jenkins
EOF

    cat << 'EOF' > compose.yaml
services:
  jenkins:
    build: .
    image: my-jenkins
    container_name: jenkins
    restart: unless-stopped
    ports:
      - "8080:8080"
      - "50000:50000"
    volumes:
      - jenkins_home:/var/jenkins_home
      - /var/run/docker.sock:/var/run/docker.sock

volumes:
  jenkins_home: 
EOF

    docker compose up --build -d

    echo "Jenkins is starting on port 8080 via Docker"
  EOT

  description = "Jenkins CI/CD VM in public subnet"
}

# ── STATIC EXTERNAL IP for Jenkins (optional but stable) ──────
resource "google_compute_address" "jenkins_ip" {
  project = var.project_id
  name    = "jenkins-static-ip"
  region  = var.region
}

# ── UNMANAGED INSTANCE GROUP for Backend VM ───────────────────
# Required for HTTP Load Balancer backend
resource "google_compute_instance_group" "backend_group" {
  project   = var.project_id
  name      = "backend-vm-group"
  zone      = var.zone
  instances = [google_compute_instance.backend_vm.id]

  # Named ports match the Load Balancer backend service
  named_port {
    name = "http"
    port = 80
  }
}
