#!/bin/bash
# Simple deployment: Build and push images, then restart deployments
# This does NOT update the GitOps repo

set -e

echo "=== Building and Deploying Todo App (Images Only) ==="

# Get commit hashes
cd "$(dirname "$0")"
BACKEND_COMMIT=$(cd backend/repo && git rev-parse --short HEAD)
FRONTEND_COMMIT=$(cd frontend/repo && git rev-parse --short HEAD)

echo "Backend commit: $BACKEND_COMMIT"
echo "Frontend commit: $FRONTEND_COMMIT"

# Build and push backend
echo ""
echo "=== Building backend image ==="
docker buildx build --platform linux/arm64,linux/amd64 \
  -t shiukaheng/todo-backend:$BACKEND_COMMIT \
  -t shiukaheng/todo-backend:latest \
  --push \
  -f backend/Dockerfile .

# Build and push frontend
echo ""
echo "=== Building frontend image ==="
docker buildx build --platform linux/arm64,linux/amd64 \
  -t shiukaheng/todo-frontend:$FRONTEND_COMMIT \
  -t shiukaheng/todo-frontend:latest \
  --push \
  -f frontend/Dockerfile .

# Restart deployments to pull new :latest images
echo ""
echo "=== Restarting deployments ==="
kubectl rollout restart deployment -n todo backend frontend

# Wait for rollout to complete
echo ""
echo "=== Waiting for rollout to complete ==="
kubectl rollout status deployment -n todo backend --timeout=300s
kubectl rollout status deployment -n todo frontend --timeout=300s

echo ""
echo "=== Deployment complete! ==="
kubectl get pods -n todo
