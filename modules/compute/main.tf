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

# ── BACKEND VM (Private Subnet) ───────────────────────────────
# e2-micro = free tier eligible (1 vCPU, 1GB RAM)
resource "google_compute_instance" "backend_vm" {
  project      = var.project_id
  name         = "backend-vm"
  machine_type = "e2-micro"  # Free tier: 1 e2-micro per month in us-central1
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
  # metadata_startup_script = <<-EOT
  #   #!/bin/bash
  #   set -e

  #   # ── Install Docker ──────────────────────────────────────
  #   apt-get update -y
  #   apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

  #   curl -fsSL https://download.docker.com/linux/debian/gpg | \
  #     gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

  #   echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
  #     https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
  #     > /etc/apt/sources.list.d/docker.list

  #   apt-get update -y
  #   apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

  #   systemctl enable docker
  #   systemctl start docker

  #   # ── Authenticate Docker with Artifact Registry ──────────
  #   gcloud auth configure-docker ${var.region}-docker.pkg.dev --quiet

  #   echo "Backend VM ready. Jenkins will deploy containers via docker-compose."
  #   echo "Artifact Registry: ${var.artifact_registry_repo}"
  # EOT

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

  # Startup script: install Java, Jenkins, Docker, gcloud
  # metadata_startup_script = <<-EOT
  #   #!/bin/bash
  #   set -e

  #   # ── System update ────────────────────────────────────────
  #   apt-get update -y
  #   apt-get install -y apt-transport-https ca-certificates curl gnupg \
  #     lsb-release software-properties-common git wget

  #   # ── Install Java 17 (Jenkins requirement) ────────────────
  #   apt-get install -y openjdk-17-jdk
  #   export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

  #   # ── Install Jenkins ──────────────────────────────────────
  #   curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | \
  #     tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
  #   echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  #     https://pkg.jenkins.io/debian-stable binary/" | \
  #     tee /etc/apt/sources.list.d/jenkins.list > /dev/null

  #   apt-get update -y
  #   apt-get install -y jenkins

  #   systemctl enable jenkins
  #   systemctl start jenkins

  #   # ── Install Docker ────────────────────────────────────────
  #   curl -fsSL https://download.docker.com/linux/debian/gpg | \
  #     gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

  #   echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
  #     https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
  #     > /etc/apt/sources.list.d/docker.list

  #   apt-get update -y
  #   apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

  #   systemctl enable docker
  #   systemctl start docker

  #   # Add jenkins user to docker group
  #   usermod -aG docker jenkins

  #   # ── Install gcloud CLI ────────────────────────────────────
  #   echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] \
  #     https://packages.cloud.google.com/apt cloud-sdk main" | \
  #     tee /etc/apt/sources.list.d/google-cloud-sdk.list > /dev/null

  #   curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
  #     apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -

  #   apt-get update -y
  #   apt-get install -y google-cloud-cli

  #   # Configure Docker auth for Artifact Registry
  #   gcloud auth configure-docker ${var.region}-docker.pkg.dev --quiet

  #   # Restart Jenkins to pick up docker group
  #   systemctl restart jenkins

  #   echo "Jenkins is running on port 8080"
  #   echo "Initial admin password: $(cat /var/lib/jenkins/secrets/initialAdminPassword)"
  # EOT

  # description = "Jenkins CI/CD VM in public subnet"
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
    name = "fastapi"
    port = 8000
  }
  named_port {
    name = "django"
    port = 8001
  }
  named_port {
    name = "node"
    port = 8002
  }
  named_port {
    name = "dotnet"
    port = 8003
  }
}
