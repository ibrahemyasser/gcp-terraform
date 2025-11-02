# GCP DevOps Challenge Infrastructure

A production-ready GCP infrastructure with private GKE cluster, Terraform IaC, and containerized application deployment.

## 🏗️ Architecture Overview

```
Internet → Load Balancer → Private GKE Cluster (restricted subnet)
                           ├─ Application Pods
                           └─ Redis
                           
Management Subnet (10.0.1.0/24)
├─ Private VM (kubectl access)
├─ NAT Gateway (outbound internet)

Restricted Subnet (10.0.2.0/24)
├─ Private GKE Cluster
├─ No direct internet access
```

## 📋 Prerequisites

- Terraform >= 1.0
- Google Cloud SDK (`gcloud` CLI)
- `kubectl` >= 1.20
- Docker
- GCP project with billing enabled

## 🚀 Quick Start

### 1. Set Up Service Account & Authentication

```bash
# Create service account for Terraform
gcloud iam service-accounts create terraform-sa --display-name="Terraform"

# Grant necessary roles
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:terraform-sa@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/editor"

# Create and download key
gcloud iam service-accounts keys create terraform-key.json \
  --iam-account=terraform-sa@PROJECT_ID.iam.gserviceaccount.com

# Export for Terraform authentication
export GOOGLE_APPLICATION_CREDENTIALS="$(pwd)/terraform-key.json"

# Authenticate gcloud
gcloud auth activate-service-account --key-file=terraform-key.json
```

**⚠️ Important**: Add `terraform-key.json` to `.gitignore` to prevent exposing credentials!

### 2. Deploy Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 3. Configure kubectl (from Management VM)

```bash
# SSH into management VM
gcloud compute ssh management-vm --zone=us-central1-b

# From management VM, configure kubectl
gcloud container clusters get-credentials gke-private-cluster \
  --zone=us-central1-b --project=PROJECT_ID
kubectl create namespace production
```

### 4. Create Image Pull Secret

```bash
# From management VM
kubectl create secret docker-registry gar-secret \
  --docker-server=us-central1-docker.pkg.dev \
  --docker-username=_json_key \
  --docker-password="$(cat terraform-key.json)" \
  -n production
```

### 5. Clone Application Repository

The application code is located at: https://github.com/ahmedzak7/GCP-2025/tree/main/DevOps-Challenge-Demo-Code-master

```bash
# From management VM
git clone https://github.com/ahmedzak7/GCP-2025.git
cd GCP-2025/DevOps-Challenge-Demo-Code-master
```

### 6. Build & Push Docker Image

```bash
# From management VM (or your local machine)
docker build -t codemaster-app:latest -f Dockerfile .
docker tag codemaster-app:latest \
  us-central1-docker.pkg.dev/PROJECT_ID/gcp-docker-repo/codemaster-app:latest
gcloud auth configure-docker us-central1-docker.pkg.dev
docker push us-central1-docker.pkg.dev/PROJECT_ID/gcp-docker-repo/codemaster-app:latest
```

### 7. Deploy to Kubernetes

```bash
# From management VM
kubectl apply -f kubernetes/
kubectl get pods -n production
```

## 🌐 Access Application

```bash
# Get load balancer IP
kubectl get services -n production

# Access via browser
curl http://<LOAD_BALANCER_IP>
```

## 🐛 Troubleshooting

```bash
# Check pod status
kubectl describe pod <POD_NAME> -n production

# View logs
kubectl logs <POD_NAME> -n production

# Check events
kubectl get events -n production --sort-by='.lastTimestamp'
```

## 🧹 Cleanup

```bash
# Delete namespace
kubectl delete namespace production

# Destroy infrastructure
cd terraform
terraform destroy
```

## 📁 Project Structure

```
.
├── terraform/           # Infrastructure code
├── kubernetes/          # K8s manifests
├── docker/             # Dockerfile & requirements
└── README.md
```

## 🔒 Security Features

- Private VPC network (no public IPs)
- Private GKE cluster with authorized networks
- NAT gateway for controlled outbound access
- Private Artifact Registry for images
- Service accounts with minimal permissions

## 📚 References

- [GCP VPC Docs](https://cloud.google.com/vpc/docs)
- [GKE Docs](https://cloud.google.com/kubernetes-engine/docs)
- [Artifact Registry](https://cloud.google.com/artifact-registry/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

---

**Version**: 1.0 | **Status**: Production Ready