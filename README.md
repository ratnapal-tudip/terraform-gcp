# 🏗️ Ratnapal GCP Infrastructure — Terraform Setup

## Architecture Overview

```
Users → Internet → Cloud CDN → Cloud Load Balancer (L7)
                                      │
                    ┌─────────────────┴──────────────────┐
                    │                                    │
             /api/* routes                         /* routes
                    │                                    │
            Backend VM (Private)              GCS Bucket (React)
            ├── FastAPI  :8000                   [CDN cached]
            ├── Django   :8001
            ├── Node     :8002
            └── .NET     :8003

Developer → GitHub → Jenkins (Public VM) → Artifact Registry
                          └──────────────────→ Deploy to Backend VM

Backend VM → Cloud SQL MySQL (Private IP, same VPC)
Private VM → Cloud NAT → Internet (outbound only)
```

---

## 📁 Project Structure

```
terraform-gcp/
├── main.tf                     # Root: calls all modules
├── variables.tf                # Root variables
├── outputs.tf                  # Root outputs
├── provider.tf                 # GCP provider config
├── terraform.tfvars            # Your values (project id, region, etc.)
├── Jenkinsfile                 # CI/CD pipeline
└── modules/
    ├── vpc/                    # VPC, subnets, NAT, firewall rules
    ├── compute/                # Backend VM + Jenkins VM
    ├── sql/                    # MySQL Cloud SQL (private IP)
    ├── storage/                # GCS bucket for React frontend
    ├── artifact_registry/      # Docker image registry
    └── load_balancer/          # HTTP LB + Cloud CDN
```

---

## 🚀 Step-by-Step Deployment

### Prerequisites

```bash
# Install Terraform
brew install terraform          # macOS
# or: https://developer.hashicorp.com/terraform/install

# Install gcloud CLI
# https://cloud.google.com/sdk/docs/install

# Authenticate
gcloud auth login
gcloud auth application-default login
gcloud config set project ratnapal-project
```

### Step 1 — Enable Required GCP APIs

```bash
gcloud services enable \
  compute.googleapis.com \
  sqladmin.googleapis.com \
  servicenetworking.googleapis.com \
  artifactregistry.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  storage.googleapis.com \
  --project=ratnapal-project
```

### Step 2 — Initialize and Deploy Terraform

```bash
cd terraform-gcp/

# Initialize providers and modules
terraform init

# Preview what will be created
terraform plan

# Apply (takes ~10-15 minutes for Cloud SQL)
terraform apply
# Type "yes" when prompted
```

### Step 3 — Note the Outputs

After apply completes, note these values:
```
load_balancer_ip        = "X.X.X.X"      ← Your app public URL
jenkins_vm_ip           = "X.X.X.X"      ← Jenkins UI: X.X.X.X:8080
backend_vm_private_ip   = "10.0.1.X"
artifact_registry_url   = "us-central1-docker.pkg.dev/ratnapal-project/ratnapal-images"
cloud_sql_private_ip    = "10.X.X.X"
```

---

## 🔧 Post-Deployment Setup

### Jenkins Initial Setup

1. Open browser: `http://<jenkins_vm_ip>:8080`
2. SSH into Jenkins VM to get the initial password:
   ```bash
   gcloud compute ssh jenkins-vm --zone=us-central1-a
   sudo cat /var/lib/jenkins/secrets/initialAdminPassword
   ```
3. Install suggested plugins + add these extra plugins:
   - **Docker Pipeline**
   - **SSH Agent**
   - **GitHub Integration**

### Jenkins Credentials to Add

Go to Jenkins → Manage Jenkins → Credentials → Global:

| ID | Type | Value |
|----|------|-------|
| `BACKEND_VM_PRIVATE_IP` | Secret text | `10.0.1.X` (from terraform output) |
| `backend-vm-ssh-key` | SSH Username with private key | Your SSH private key |

### Add SSH Key to Backend VM

```bash
# On Jenkins VM, generate a key pair
ssh-keygen -t ed25519 -C "jenkins@ratnapal" -f ~/.ssh/jenkins_key

# Add public key to backend VM metadata (so Jenkins can SSH in)
gcloud compute instances add-metadata backend-vm \
  --metadata ssh-keys="jenkins:$(cat ~/.ssh/jenkins_key.pub)" \
  --zone=us-central1-a

# Add private key to Jenkins credentials (ID: backend-vm-ssh-key)
cat ~/.ssh/jenkins_key
```

### Configure GitHub Webhook

1. Go to your GitHub repo → Settings → Webhooks → Add webhook
2. Payload URL: `http://<jenkins_vm_ip>:8080/github-webhook/`
3. Content type: `application/json`
4. Events: Just the push event

### Create Jenkins Pipeline Job

1. New Item → Pipeline
2. Build Triggers → ✅ GitHub hook trigger for GITScm polling
3. Pipeline → Pipeline script from SCM → Git
4. Repository URL: your GitHub repo URL
5. Script Path: `Jenkinsfile`

---

## 🐳 Docker Compose on Backend VM

Your repo's `docker-compose.yml` should use Artifact Registry images:

```yaml
# Example docker-compose.yml structure
version: "3.8"
services:
  fastapi:
    image: us-central1-docker.pkg.dev/ratnapal-project/ratnapal-images/fastapi:latest
    ports: ["8000:8000"]
    environment:
      - DB_HOST=<cloud_sql_private_ip>
      - DB_USER=root
      - DB_PASS=Admin@123
      - DB_NAME=appdb

  django:
    image: us-central1-docker.pkg.dev/ratnapal-project/ratnapal-images/django:latest
    ports: ["8001:8000"]
    environment:
      - DB_HOST=<cloud_sql_private_ip>
      - DB_USER=root
      - DB_PASSWORD=Admin@123
      - DB_NAME=appdb

  node:
    image: us-central1-docker.pkg.dev/ratnapal-project/ratnapal-images/node:latest
    ports: ["8002:3000"]
    environment:
      - DB_HOST=<cloud_sql_private_ip>

  dotnet:
    image: us-central1-docker.pkg.dev/ratnapal-project/ratnapal-images/dotnet:latest
    ports: ["8003:80"]
    environment:
      - DB_HOST=<cloud_sql_private_ip>
```

---

## 🌐 React Frontend Deployment

Upload your React build to GCS:
```bash
# Build your React app
npm run build

# Upload to GCS bucket
gsutil -m cp -r build/* gs://ratnapal-project-react-frontend/

# Set cache headers
gsutil -m setmeta -h "Cache-Control:public, max-age=3600" \
  gs://ratnapal-project-react-frontend/**
```

Your React app will be served at: `http://<load_balancer_ip>/`
API routes at: `http://<load_balancer_ip>/api/*`

---

## 💰 Free Tier Notes

| Resource | Free Tier Limit | What We Use |
|----------|----------------|-------------|
| Compute e2-micro | 1 VM/month (us-central1) | 1 backend VM (e2-micro) ✅ |
| Jenkins VM | Not free-tier | e2-medium (~$26/mo) |
| Cloud SQL db-f1-micro | Not free-tier | ~$7-10/mo |
| Cloud Storage | 5 GB free | < 1 GB ✅ |
| Artifact Registry | 0.5 GB free | Small ✅ |
| Cloud CDN | 10 GB egress free | Likely free ✅ |
| Cloud NAT | ~$1/mo | Minimal |

> **Tip**: Use GCP's 90-day $300 free trial to cover Jenkins VM and Cloud SQL costs.
> Backend VM (e2-micro) stays free after trial.

---

## 🔒 Security Hardening (For Production)

1. Restrict Jenkins firewall rule to your IP only:
   ```hcl
   # In modules/vpc/main.tf → allow_jenkins_access
   source_ranges = ["YOUR.IP.HERE/32"]
   ```

2. Add HTTPS to Load Balancer (requires a domain + SSL cert)

3. Use Secret Manager for DB credentials instead of hardcoding

4. Enable Cloud SQL automated backups

5. Set `deletion_protection = true` on Cloud SQL

---

## 🗑️ Teardown

```bash
terraform destroy
# Type "yes" to delete all resources
```
