#!/bin/bash
# Full GitOps deployment: Build images, update GitOps repo, sync ArgoCD
# This keeps Git as the source of truth

set -e

echo "=== Building and Deploying Todo App (GitOps) ==="

# Configuration
GITOPS_REPO="../../k3s-ldn-gitops"
DEPLOYMENT_FILE="apps/todo/deployment.yaml"

# Get commit hashes
cd "$(dirname "$0")/.."
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
  --build-arg BASE_PATH=/todo/ \
  -t shiukaheng/todo-frontend:$FRONTEND_COMMIT \
  -t shiukaheng/todo-frontend:latest \
  --push \
  -f frontend/Dockerfile .

# Update GitOps repo
echo ""
echo "=== Updating GitOps repo ==="
cd "$GITOPS_REPO"

# Update backend image tag
sed -i "s|image: shiukaheng/todo-backend:.*|image: shiukaheng/todo-backend:$BACKEND_COMMIT|" "$DEPLOYMENT_FILE"

# Update frontend image tag
sed -i "s|image: shiukaheng/todo-frontend:.*|image: shiukaheng/todo-frontend:$FRONTEND_COMMIT|" "$DEPLOYMENT_FILE"

# Commit and push
git add "$DEPLOYMENT_FILE"
git commit -m "Update todo app: backend $BACKEND_COMMIT, frontend $FRONTEND_COMMIT" || {
  echo "No changes to commit"
  exit 0
}
git push

# Sync ArgoCD (optional - ArgoCD will auto-sync, but this forces it immediately)
echo ""
echo "=== Syncing ArgoCD ==="
kubectl patch application todo -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# Wait for sync
echo ""
echo "=== Waiting for ArgoCD to sync ==="
sleep 5  # Give ArgoCD time to detect changes

# Wait for rollout to complete
echo ""
echo "=== Waiting for rollout to complete ==="
kubectl rollout status deployment -n todo backend --timeout=300s
kubectl rollout status deployment -n todo frontend --timeout=300s

echo ""
echo "=== Deployment complete! ==="
kubectl get pods -n todo
echo ""
echo "Deployed versions:"
echo "  Backend:  $BACKEND_COMMIT"
echo "  Frontend: $FRONTEND_COMMIT"
