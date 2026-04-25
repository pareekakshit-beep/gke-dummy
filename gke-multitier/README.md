# GKE Multi-Tier Store — Dummy Project

A real deployable demo project for learning GCP + Kubernetes multi-tier architecture.

## Architecture

```
INTERNET
    │
    ▼
┌─────────────────────────────────────────────────────────┐
│  GCP External Load Balancer  (public IP: created by GKE) │
└─────────────────────────────────────────────────────────┘
    │  Port 80
    ▼
┌──────────────────────────── WEB TIER ──────────────────────────────┐
│  frontend Deployment (2 pods)                                       │
│  Image: Nginx 1.25                                                  │
│  Service: frontend-service  → type: LoadBalancer (public)          │
│  • Serves index.html                                                │
│  • Proxies /api/* → backend-service:3000 (internal DNS)            │
└────────────────────────────────────────────────────────────────────┘
    │  ClusterIP:3000 (inside cluster only)
    ▼
┌──────────────────────────── APP TIER ──────────────────────────────┐
│  backend Deployment (2 pods, HPA: 2–10)                            │
│  Image: Node.js 20 + Express                                       │
│  Service: backend-service  → type: ClusterIP (private)            │
│  Endpoints:                                                         │
│    GET  /health           → health check                           │
│    GET  /api/products     → list all products                      │
│    POST /api/products     → create product                         │
│    GET  /api/products/:id → get one product                        │
│    DELETE /api/products/:id → delete product                      │
│  Reads DB credentials from: Secret + ConfigMap                     │
└────────────────────────────────────────────────────────────────────┘
    │  ClusterIP:5432 (inside cluster only)
    ▼
┌──────────────────────────── DATA TIER ─────────────────────────────┐
│  postgres StatefulSet (1 pod: postgres-0)                          │
│  Image: PostgreSQL 16                                               │
│  Service: postgres-service  → type: ClusterIP (private)           │
│  PersistentVolumeClaim: 5Gi GCP Persistent Disk (standard-rwo)    │
│  Data survives pod restarts ✅                                      │
└────────────────────────────────────────────────────────────────────┘
```

## Network Security (NetworkPolicy)
```
Internet  →  frontend (80)  ALLOWED
frontend  →  backend  (3000) ALLOWED
backend   →  postgres (5432) ALLOWED
Internet  →  backend  BLOCKED ❌
Internet  →  postgres BLOCKED ❌
frontend  →  postgres BLOCKED ❌
```

## Project Structure
```
gke-multitier/
├── backend/
│   ├── server.js          Node.js Express API
│   ├── package.json
│   └── Dockerfile         Multi-stage build, non-root user
├── frontend/
│   ├── index.html         Full product store UI
│   ├── nginx.conf         Nginx reverse proxy config
│   └── Dockerfile
├── k8s/
│   ├── 00-namespace.yaml          Namespace: store
│   ├── 01-configmap.yaml          DB host, port, name (non-secret)
│   ├── 02-secret.yaml             DB password (sensitive)
│   ├── 03-postgres-statefulset.yaml  Data tier + ClusterIP service
│   ├── 04-backend-deployment.yaml    App tier + ClusterIP service
│   ├── 05-frontend-deployment.yaml   Web tier + LoadBalancer service
│   ├── 06-hpa.yaml                HorizontalPodAutoscaler (auto-scaling)
│   └── 07-network-policy.yaml     Zero-trust network rules
└── setup.sh               Step-by-step GCP + kubectl commands
```

## Prerequisites
- GCP project with billing enabled
- `gcloud` CLI installed and authenticated
- `kubectl` installed
- `docker` installed

## Quick Steps

### 1. Set variables
```bash
export PROJECT_ID="your-project-id"
export REGION="asia-south1"
```

### 2. Enable APIs & create Artifact Registry
```bash
gcloud services enable container.googleapis.com artifactregistry.googleapis.com
gcloud artifacts repositories create store-repo --repository-format=docker --location=$REGION
gcloud auth configure-docker ${REGION}-docker.pkg.dev
```

### 3. Build and push images
```bash
IMAGE_BASE="${REGION}-docker.pkg.dev/${PROJECT_ID}/store-repo"
docker build -t ${IMAGE_BASE}/store-backend:latest ./backend && docker push $_
docker build -t ${IMAGE_BASE}/store-frontend:latest ./frontend && docker push $_
```

### 4. Update image names in manifests
```bash
sed -i "s/YOUR_PROJECT_ID/${PROJECT_ID}/g" k8s/04-backend-deployment.yaml k8s/05-frontend-deployment.yaml
```

### 5. Create GKE Autopilot cluster (~5 min)
```bash
gcloud container clusters create-auto store-cluster --region=$REGION
gcloud container clusters get-credentials store-cluster --region=$REGION
```

### 6. Deploy in order
```bash
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-configmap.yaml
kubectl apply -f k8s/02-secret.yaml
kubectl apply -f k8s/03-postgres-statefulset.yaml
kubectl wait --for=condition=ready pod/postgres-0 -n store --timeout=300s
kubectl apply -f k8s/04-backend-deployment.yaml
kubectl apply -f k8s/05-frontend-deployment.yaml
kubectl apply -f k8s/06-hpa.yaml
kubectl apply -f k8s/07-network-policy.yaml
```

### 7. Get public IP
```bash
kubectl get service frontend-service -n store --watch
# Visit http://EXTERNAL-IP when EXTERNAL-IP is no longer <pending>
```

## What You'll Learn From This Project
- **Namespace** — logical isolation of all store resources
- **StatefulSet** — why databases need stable pod names + storage
- **Deployment** — stateless pods with rolling updates
- **Service types** — ClusterIP (private) vs LoadBalancer (public)
- **ConfigMap** — inject non-sensitive config as env vars
- **Secret** — inject sensitive data (passwords) securely
- **initContainer** — wait for DB before starting app
- **HPA** — automatic pod scaling based on CPU/memory
- **NetworkPolicy** — Kubernetes firewall between tiers
- **PersistentVolumeClaim** — GCP Persistent Disk attached to DB pod
- **Health probes** — readiness + liveness probes on all containers
