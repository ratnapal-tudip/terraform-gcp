# 🚀 Jenkins CI/CD Automation on GCP — Complete Guide

> **Project**: Ratnapal 3-Tier Cloud Application  
> **Region**: us-central1 | **Zone**: us-central1-a  
> **Repo**: [cloud-3tier-project](https://github.com/ratnapal-tudip/cloud-3tier-project.git)

---

## 📋 Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [What Gets Automated](#what-gets-automated)
3. [Prerequisites](#prerequisites)
4. [Step-by-Step Deployment](#step-by-step-deployment)
5. [Post-Deployment Verification](#post-deployment-verification)
6. [GitHub Webhook Setup](#github-webhook-setup)
7. [Jenkins Credentials Reference](#jenkins-credentials-reference)
8. [How GCP Authentication Works](#how-gcp-authentication-works)
9. [Troubleshooting](#troubleshooting)
10. [File Structure](#file-structure)

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     GCP Project                             │
│                                                             │
│  ┌─────────────────────┐     ┌─────────────────────────┐   │
│  │   Public Subnet      │     │   Private Subnet         │   │
│  │                       │     │                           │   │
│  │  ┌─────────────────┐ │     │  ┌─────────────────────┐ │   │
│  │  │  Jenkins VM      │ │     │  │   Backend VM         │ │   │
│  │  │  (e2-medium)     │ │SSH  │  │   (e2-medium)        │ │   │
│  │  │                  │─┼─────┼──│                      │ │   │
│  │  │  - Docker        │ │     │  │  - Docker             │ │   │
│  │  │  - Jenkins+JCasC │ │     │  │  - FastAPI            │ │   │
│  │  │  - gcloud CLI    │ │     │  │  - Django             │ │   │
│  │  │  - Node.js       │ │     │  │  - Node.js            │ │   │
│  │  │  :8080 (Web UI)  │ │     │  │  - .NET               │ │   │
│  │  └─────────────────┘ │     │  └─────────────────────┘ │   │
│  └─────────────────────┘     └─────────────────────────┘   │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ Artifact     │  │ Cloud SQL    │  │ GCS Bucket       │  │
│  │ Registry     │  │ (MySQL)      │  │ (React Frontend) │  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │          HTTP Load Balancer (Global)                  │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## ✅ What Gets Automated

Everything below is **fully automated** via Terraform + Jenkins Configuration as Code (JCasC):

| Component | Details |
|-----------|---------|
| **Jenkins User** | `ratnapal` / `admin` — browser login enabled |
| **Setup Wizard** | Skipped entirely (JCasC handles config) |
| **Plugins** | ssh-agent, git, github, pipeline, docker, credentials, JCasC, job-dsl |
| **Pipeline Job** | `cloud-3tier-pipeline` — SCM on `main` branch |
| **GitHub Webhook** | Trigger configured (you add the URL on GitHub) |
| **Credential: BACKEND_VM_PRIVATE_IP** | Auto-injected from Terraform output |
| **Credential: backend-vm-ssh-key** | SSH private key pre-configured |
| **GCP Auth** | Uses VM service account metadata (free, no JSON key) |

---

## 📌 Prerequisites

Before running `terraform apply`, ensure:

1. **GCP Project** exists: `ratnapal-project`
2. **gcloud CLI** installed and authenticated locally:
   ```bash
   gcloud auth login
   gcloud config set project ratnapal-project
   gcloud auth application-default login
   ```
3. **Terraform** installed (>= 1.5.0):
   ```bash
   terraform version
   ```
4. **APIs enabled** on the GCP project:
   ```bash
   gcloud services enable compute.googleapis.com \
     artifactregistry.googleapis.com \
     sqladmin.googleapis.com \
     cloudresourcemanager.googleapis.com
   ```
5. **SSH key pair** generated (already done):
   - Public: `gcp_key.pub`
   - Private: `gcp_key`

---

## 🚀 Step-by-Step Deployment

### Step 1: Clone and Navigate

```bash
cd ~/terraform-gcp
```

### Step 2: Initialize Terraform

```bash
terraform init
```

### Step 3: Review the Plan

```bash
terraform plan
```

Review the output. You should see resources being created for:
- VPC + subnets + NAT + firewall rules
- Artifact Registry
- Cloud SQL (MySQL)
- GCS Bucket (frontend)
- Backend VM (private subnet)
- Jenkins VM (public subnet, with JCasC)
- Load Balancer

### Step 4: Apply

```bash
terraform apply
```

Type `yes` when prompted. This will take **5-10 minutes**.

### Step 5: Get Outputs

```bash
terraform output
```

You'll see:
```
jenkins_vm_ip          = "<EPHEMERAL_IP>"
backend_vm_private_ip  = "10.x.x.x"
load_balancer_ip       = "<LB_IP>"
artifact_registry_url  = "us-central1-docker.pkg.dev/ratnapal-project/ratnapal-images"
frontend_bucket_url    = "gs://ratnapal-project-react-frontend"
cloud_sql_private_ip   = "10.x.x.x"
```

> ⚠️ **Save the `jenkins_vm_ip`** — you need it for the GitHub webhook.  
> Since we're using an ephemeral IP (no extra cost), this IP **will change** if the VM restarts.

### Step 6: Wait for Jenkins to Start

The Jenkins VM startup script takes **3-5 minutes** after the VM is created:
1. Installs Docker
2. Builds the custom Jenkins image (with plugins)
3. Launches Jenkins via Docker Compose

You can monitor progress by SSHing into the Jenkins VM:
```bash
gcloud compute ssh jenkins-vm --zone=us-central1-a --project=ratnapal-project
# Then check startup script logs:
sudo journalctl -u google-startup-scripts.service -f
```

### Step 7: Access Jenkins

Open in browser:
```
http://<JENKINS_VM_IP>:8080
```

Login with:
- **Username**: `ratnapal`
- **Password**: `admin`

You should see the `cloud-3tier-pipeline` job already created! 🎉

---

## ✅ Post-Deployment Verification

### Verify Jenkins User
1. Go to `http://<JENKINS_VM_IP>:8080`
2. Login with `ratnapal` / `admin`
3. You should land on the Jenkins dashboard

### Verify Pipeline Job
1. Click on `cloud-3tier-pipeline` in the dashboard
2. Verify the configuration:
   - SCM: Git → `https://github.com/ratnapal-tudip/cloud-3tier-project.git`
   - Branch: `*/main`
   - Script Path: `Jenkinsfile`
   - Build Trigger: GitHub hook trigger for GITScm polling ✓

### Verify Credentials
1. Go to **Manage Jenkins** → **Credentials** → **System** → **Global credentials**
2. You should see:
   - `BACKEND_VM_PRIVATE_IP` (Secret text) — contains the backend VM's private IP
   - `backend-vm-ssh-key` (SSH Username with private key) — contains your ed25519 key

### Verify Plugins
1. Go to **Manage Jenkins** → **Plugins** → **Installed plugins**
2. Confirm these are installed:
   - SSH Agent
   - Git
   - GitHub Integration
   - Pipeline
   - Configuration as Code
   - Docker Pipeline
   - Credentials Binding

---

## 🔗 GitHub Webhook Setup

### Step 1: Get Jenkins URL
```bash
terraform output jenkins_vm_ip
```

### Step 2: Configure on GitHub
1. Go to: https://github.com/ratnapal-tudip/cloud-3tier-project/settings/hooks
2. Click **"Add webhook"**
3. Fill in:

| Field | Value |
|-------|-------|
| **Payload URL** | `http://<JENKINS_VM_IP>:8080/github-webhook/` |
| **Content type** | `application/json` |
| **Secret** | *(leave empty)* |
| **Events** | Just the push event |
| **Active** | ✓ Checked |

4. Click **"Add webhook"**

### Step 3: Test It
1. Make a commit to the `main` branch of `cloud-3tier-project`
2. Push to GitHub
3. Check Jenkins — a new build should trigger automatically

> ⚠️ **Important**: Since Jenkins uses an ephemeral IP, you'll need to update the webhook URL whenever the Jenkins VM restarts with a new IP.

---

## 🔑 Jenkins Credentials Reference

| Credential ID | Type | Value Source | Used In |
|---------------|------|-------------|---------|
| `BACKEND_VM_PRIVATE_IP` | Secret Text | Terraform output (auto-injected) | Jenkinsfile line 8: `credentials('BACKEND_VM_PRIVATE_IP')` |
| `backend-vm-ssh-key` | SSH Private Key | Your `gcp_key` (ed25519) | Jenkinsfile line 148: `sshagent(['backend-vm-ssh-key'])` |

---

## ☁️ How GCP Authentication Works

**No JSON key file needed!** Here's how it works:

1. Terraform creates a **Service Account** (`ratnapal-vm-sa`) with these roles:
   - `roles/artifactregistry.writer` — Push Docker images
   - `roles/storage.objectAdmin` — Upload frontend to GCS
   - `roles/compute.networkViewer` — Fetch LB IP
   - `roles/logging.logWriter` — Cloud Logging
   - `roles/monitoring.metricWriter` — Cloud Monitoring

2. Both VMs use this service account with `cloud-platform` scope

3. Inside the Jenkins container, `gcloud` automatically authenticates via the **VM metadata server** (the underlying VM's service account credentials are available to containers)

4. The Jenkinsfile runs:
   ```bash
   gcloud auth configure-docker us-central1-docker.pkg.dev --quiet
   ```
   This configures Docker to use the service account for pushing to Artifact Registry.

**Cost**: $0 — Service account metadata auth is free and included in GCP free tier.

---

## 🔧 Troubleshooting

### Jenkins not accessible on :8080

```bash
# SSH into Jenkins VM
gcloud compute ssh jenkins-vm --zone=us-central1-a --project=ratnapal-project

# Check if startup script finished
sudo journalctl -u google-startup-scripts.service --no-pager | tail -30

# Check if Docker is running
sudo docker ps

# Check Jenkins container logs
sudo docker logs jenkins
```

### Jenkins shows setup wizard instead of login

This means JCasC didn't load properly:
```bash
# SSH into Jenkins VM
gcloud compute ssh jenkins-vm --zone=us-central1-a

# Check if casc.yaml exists and has correct content
sudo cat /opt/jenkins/casc.yaml

# Check Jenkins container environment
sudo docker exec jenkins env | grep CASC

# Check Jenkins logs for JCasC errors
sudo docker logs jenkins 2>&1 | grep -i "casc\|configuration"
```

### SSH to backend VM fails from Jenkins pipeline

```bash
# From Jenkins VM, test SSH manually:
sudo docker exec -it jenkins bash
ssh -i /tmp/test_key -o StrictHostKeyChecking=no ratnapalshende2001_gmail_com@<BACKEND_VM_PRIVATE_IP>
```

If it fails, check:
1. Backend VM firewall allows SSH from Jenkins VM (internal traffic rule)
2. SSH key metadata is set correctly on backend VM:
   ```bash
   gcloud compute instances describe backend-vm --zone=us-central1-a --format="value(metadata.items)"
   ```

### Pipeline fails at "Authenticate with GCP"

The service account might not have the right permissions:
```bash
# Check service account roles
gcloud projects get-iam-policy ratnapal-project \
  --flatten="bindings[].members" \
  --filter="bindings.members:ratnapal-vm-sa" \
  --format="table(bindings.role)"
```

### Re-applying after Jenkins VM IP changes

If the Jenkins VM gets a new IP (restart/recreate):
1. Get new IP: `terraform output jenkins_vm_ip`
2. Update GitHub webhook with new URL
3. Jenkins config persists in the Docker volume

---

## 📁 File Structure

```
terraform-gcp/
├── main.tf                          # Root module — wires all modules
├── variables.tf                     # Root variables (project_id, region, zone)
├── outputs.tf                       # Root outputs (IPs, URLs)
├── terraform.tfvars                 # Variable values
├── provider.tf                      # GCP provider config
├── Jenkinsfile                      # Pipeline definition (in app repo too)
├── .env                             # DB connection config
│
├── jenkins/                         # Local reference copies
│   ├── Dockerfile                   # Jenkins image with Docker+gcloud+Node+plugins
│   ├── compose.yaml                 # Docker Compose for Jenkins
│   └── plugins.txt                  # Jenkins plugins list
│
├── modules/
│   ├── compute/
│   │   ├── main.tf                  # ⭐ VMs + JCasC automation
│   │   ├── variables.tf             # Module variables
│   │   ├── outputs.tf               # VM IPs, instance group
│   │   ├── jenkins-casc.yaml        # JCasC template (reference)
│   │   └── jenkins-plugins.txt      # Plugins list (reference)
│   ├── vpc/                         # VPC, subnets, NAT, firewall
│   ├── artifact_registry/           # Docker image registry
│   ├── sql/                         # Cloud SQL (MySQL)
│   ├── storage/                     # GCS bucket for frontend
│   └── load_balancer/               # HTTP(S) Load Balancer
│
└── readme_guide.md                  # ← You are here
```

---

## 🔄 Pipeline Flow (What Happens on Push)

```
GitHub Push (main branch)
    │
    ▼
GitHub Webhook → http://<JENKINS_IP>:8080/github-webhook/
    │
    ▼
Jenkins triggers 'cloud-3tier-pipeline'
    │
    ├── 1. Checkout source code
    ├── 2. Set commit tag (git short hash)
    ├── 3. Authenticate with GCP (gcloud)
    ├── 4. Build Docker images (parallel: FastAPI, Django, Node, .NET)
    ├── 5. Push to Artifact Registry (parallel)
    ├── 6. Build React frontend → Upload to GCS
    └── 7. Deploy to Backend VM via SSH
         ├── SCP compose.yaml
         ├── docker compose pull
         └── docker compose up -d
```

---

## 💡 Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Ephemeral IP** (no static) | Static IPs cost ~$3/month when attached; save money on free tier |
| **JCasC** (not manual setup) | Fully reproducible — `terraform destroy` + `terraform apply` gives you identical Jenkins |
| **Metadata SSH keys** (not OS Login) on Backend VM | OS Login requires Google account UID; metadata keys are simpler for automation |
| **VM service account** (not JSON key) | Free, auto-rotated, no key file to manage or leak |
| **Plugins in Dockerfile** (not runtime install) | Faster boot — plugins are baked into the image |
| **Docker-in-Docker** via socket mount | Jenkins container can build/push Docker images using the host's Docker daemon |

---

## 🧹 Tear Down

To destroy all resources:
```bash
terraform destroy
```

Type `yes` to confirm. All GCP resources will be deleted.

---

*Generated for Ratnapal's 3-Tier Cloud Project — April 2026*
