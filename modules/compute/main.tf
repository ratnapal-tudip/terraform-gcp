###############################################################
# MODULE: COMPUTE
# - Service Account for VMs
# - Backend VM (private subnet) — runs 4 Docker containers
# - Jenkins VM (public subnet)  — CI/CD pipeline (fully automated via JCasC)
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
# e2-micro = free tier eligible (1 vCPU, 1GB RAM) (changed because it was lagging)
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

  # Use metadata SSH keys instead of OS Login for Jenkins SSH access
  metadata = {
    ssh-keys = "ratnapalshende2001_gmail_com:ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJJBC8y7JXRGQWrTKDLnALbkHFZ8AuLoeATbIitlgkMV ratnapal"
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
# Fully automated: JCasC configures user, credentials, pipeline, plugins
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

  # Startup script: install Docker, build Jenkins image with JCasC, launch
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

    # ── Setup Jenkins via Docker (fully automated) ─────────────
    mkdir -p /opt/jenkins
    cd /opt/jenkins

    # Give Jenkins container permission to talk to Docker socket
    chmod 666 /var/run/docker.sock

    # ── Write plugins list ──────────────────────────────────────
    cat << 'PLUGINS' > plugins.txt
configuration-as-code
workflow-aggregator
git
github
github-branch-source
ssh-agent
ssh-credentials
credentials
credentials-binding
job-dsl
pipeline-stage-view
docker-workflow
docker-plugin
dark-theme
PLUGINS

    # ── Write Dockerfile ─────────────────────────────────────────
    cat << 'DOCKERFILE' > Dockerfile
FROM jenkins/jenkins:lts

USER root

RUN apt-get update && \
    apt-get install -y ca-certificates curl gnupg && \
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

# Install plugins from list
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Skip setup wizard
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
ENV CASC_JENKINS_CONFIG="/var/jenkins_config/casc.yaml"

USER jenkins
DOCKERFILE

    # ── Write JCasC configuration ────────────────────────────────
    cat << 'CASC' > casc.yaml
jenkins:
  securityRealm:
    local:
      allowsSignup: false
      users:
        - id: "ratnapal"
          password: "admin"
  authorizationStrategy:
    loggedInUsersCanDoAnything:
      allowAnonymousRead: false
  numExecutors: 2

credentials:
  system:
    domainCredentials:
      - credentials:
          - string:
              scope: GLOBAL
              id: "BACKEND_VM_PRIVATE_IP"
              secret: "PLACEHOLDER_BACKEND_IP"
              description: "Private IP of the Backend VM"
          - basicSSHUserPrivateKey:
              scope: GLOBAL
              id: "backend-vm-ssh-key"
              username: "ratnapalshende2001_gmail_com"
              privateKeySource:
                directEntry:
                  privateKey: |
                    -----BEGIN OPENSSH PRIVATE KEY-----
                    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
                    QyNTUxOQAAACCSQQvMuyV0RkFq0ygy5wC25BxWfALi6HgE2yIrZYJDFQAAAJDBGkcdwRpH
                    HQAAAAtzc2gtZWQyNTUxOQAAACCSQQvMuyV0RkFq0ygy5wC25BxWfALi6HgE2yIrZYJDFQ
                    AAAECk8YFJiHu5NrAjBso/vbqkVFoAG/RHpRmJrWN6Lir7AZJBC8y7JXRGQWrTKDLnALbk
                    HFZ8AuLoeATbIitlgkMVAAAACHJhdG5hcGFsAQIDBAU=
                    -----END OPENSSH PRIVATE KEY-----
              description: "SSH key for Backend VM"

jobs:
  - script: |
      pipelineJob('cloud-3tier-pipeline') {
        triggers {
          githubPush()
        }
        definition {
          cpsScm {
            scm {
              git {
                remote {
                  url('https://github.com/ratnapal-tudip/cloud-3tier-project.git')
                }
                branches('*/main')
              }
            }
            scriptPath('Jenkinsfile')
          }
        }
      }

unclassified:
  location:
    url: "http://localhost:8080/"
CASC

    # ── Replace placeholder with actual backend VM IP ────────────
    BACKEND_IP="${google_compute_instance.backend_vm.network_interface[0].network_ip}"
    sed -i "s|PLACEHOLDER_BACKEND_IP|$BACKEND_IP|g" casc.yaml

    # ── Write docker-compose file ────────────────────────────────
    cat << 'COMPOSE' > compose.yaml
services:
  jenkins:
    build: .
    image: my-jenkins
    container_name: jenkins
    restart: unless-stopped
    ports:
      - "8080:8080"
      - "50000:50000"
    environment:
      - JAVA_OPTS=-Djenkins.install.runSetupWizard=false
      - CASC_JENKINS_CONFIG=/var/jenkins_config/casc.yaml
    volumes:
      - jenkins_home:/var/jenkins_home
      - /var/run/docker.sock:/var/run/docker.sock
      - ./casc.yaml:/var/jenkins_config/casc.yaml:ro

volumes:
  jenkins_home:
COMPOSE

    # ── Build and launch Jenkins ─────────────────────────────────
    docker compose up --build -d

    echo "Jenkins is starting on port 8080 with full automation (JCasC)"
    echo "User: ratnapal | Backend VM IP: $BACKEND_IP"
  EOT

  description = "Jenkins CI/CD VM in public subnet (automated via JCasC)"
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
