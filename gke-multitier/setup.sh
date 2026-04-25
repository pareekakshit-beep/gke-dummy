#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════
#  GKE Multi-Tier Store — Complete Setup Script
#  Run each block manually in Cloud Shell or your terminal.
#  DO NOT run the entire script at once — read each step first.
# ═══════════════════════════════════════════════════════════════════════

# ── STEP 0: Set your variables ─────────────────────────────────────────
export PROJECT_ID="feasibility-491311"       # Your GCP project ID
export REGION="asia-south1"                  # Mumbai — matches your TeraCheck
export CLUSTER_NAME="store-cluster"
export REPO_NAME="store-repo"

echo "Project:  $PROJECT_ID"
echo "Region:   $REGION"
echo "Cluster:  $CLUSTER_NAME"

# ── STEP 1: Enable required APIs ───────────────────────────────────────
echo ">>> Enabling APIs..."
gcloud services enable \
  container.googleapis.com \
  artifactregistry.googleapis.com \
  --project=$PROJECT_ID

# ── STEP 2: Create Artifact Registry repo for Docker images ────────────
echo ">>> Creating Artifact Registry repository..."
gcloud artifacts repositories create $REPO_NAME \
  --repository-format=docker \
  --location=$REGION \
  --description="GKE Store multi-tier demo images" \
  --project=$PROJECT_ID

# Authenticate Docker to push to Artifact Registry
gcloud auth configure-docker ${REGION}-docker.pkg.dev

# ── STEP 3: Build & push Docker images ─────────────────────────────────
# Go to the project root (where backend/ and frontend/ folders are)
# cd /path/to/gke-multitier

IMAGE_BASE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}"

echo ">>> Building backend image..."
docker build -t ${IMAGE_BASE}/store-backend:latest ./backend
docker push ${IMAGE_BASE}/store-backend:latest

echo ">>> Building frontend image..."
docker build -t ${IMAGE_BASE}/store-frontend:latest ./frontend
docker push ${IMAGE_BASE}/store-frontend:latest

# ── STEP 4: Update image names in K8s manifests ────────────────────────
# Replace YOUR_PROJECT_ID in the deployment files
sed -i "s/YOUR_PROJECT_ID/${PROJECT_ID}/g" \
  k8s/04-backend-deployment.yaml \
  k8s/05-frontend-deployment.yaml

echo ">>> Updated image paths in manifests"

# ── STEP 5: Create GKE Autopilot cluster ───────────────────────────────
# Autopilot = Google manages nodes, scaling, patching.
# You only manage your pods and namespaces.
echo ">>> Creating GKE Autopilot cluster (takes ~5 minutes)..."
gcloud container clusters create-auto $CLUSTER_NAME \
  --region=$REGION \
  --project=$PROJECT_ID

# This takes 3–8 minutes. You'll see the cluster in Console:
# Navigation > Kubernetes Engine > Clusters

# ── STEP 6: Connect kubectl to the cluster ─────────────────────────────
echo ">>> Getting cluster credentials..."
gcloud container clusters get-credentials $CLUSTER_NAME \
  --region=$REGION \
  --project=$PROJECT_ID

# Verify kubectl is connected
kubectl cluster-info
kubectl get nodes      # Autopilot shows no nodes until pods are scheduled

# ── STEP 7: Deploy all Kubernetes resources (in order) ─────────────────
echo ">>> Deploying to Kubernetes..."

kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-configmap.yaml
kubectl apply -f k8s/02-secret.yaml
kubectl apply -f k8s/03-postgres-statefulset.yaml

# Wait for Postgres to be ready before deploying backend
echo ">>> Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=ready pod/postgres-0 \
  --namespace=store \
  --timeout=300s

kubectl apply -f k8s/04-backend-deployment.yaml
kubectl apply -f k8s/05-frontend-deployment.yaml
kubectl apply -f k8s/06-hpa.yaml
kubectl apply -f k8s/07-network-policy.yaml

# ── STEP 8: Check everything is running ────────────────────────────────
echo ">>> Checking deployment status..."

kubectl get all -n store
# You should see:
#   pod/postgres-0         — Running (StatefulSet, data tier)
#   pod/backend-xxx        — Running (Deployment x2, app tier)
#   pod/frontend-xxx       — Running (Deployment x2, web tier)
#   service/postgres-service   — ClusterIP (internal only)
#   service/backend-service    — ClusterIP (internal only)
#   service/frontend-service   — LoadBalancer (PUBLIC IP here!)

# ── STEP 9: Get the public IP ──────────────────────────────────────────
echo ">>> Waiting for LoadBalancer IP (may take 2-3 minutes)..."
kubectl get service frontend-service -n store --watch
# Wait until EXTERNAL-IP column shows an IP (not <pending>)

# Or run this to get just the IP:
kubectl get service frontend-service -n store \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# ── STEP 10: Open in browser ───────────────────────────────────────────
# Visit http://EXTERNAL-IP in your browser
# You should see the GKE Store UI with sample products

# ── USEFUL DEBUG COMMANDS ──────────────────────────────────────────────

# View logs from backend pods
kubectl logs -l app=backend -n store --tail=50

# View logs from frontend pods  
kubectl logs -l app=frontend -n store --tail=20

# View logs from postgres
kubectl logs pod/postgres-0 -n store --tail=50

# Exec into backend pod (like SSH into it)
kubectl exec -it deployment/backend -n store -- sh

# Exec into postgres and run SQL
kubectl exec -it pod/postgres-0 -n store -- \
  psql -U storeuser -d storedb -c "SELECT * FROM products;"

# Check HPA (autoscaler) status
kubectl get hpa -n store

# Check network policies
kubectl get networkpolicies -n store

# Describe a pod if it's not starting
kubectl describe pod/postgres-0 -n store

# Watch all pods in real time
kubectl get pods -n store -w

# ── CLEANUP — delete everything when done ─────────────────────────────
# kubectl delete namespace store           # Deletes all K8s resources
# gcloud container clusters delete $CLUSTER_NAME --region=$REGION
# (Cluster deletion stops GKE billing)
