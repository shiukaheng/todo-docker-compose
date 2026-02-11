# Todo App Deployment Guide

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     User Browser                             │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ↓
┌─────────────────────────────────────────────────────────────┐
│            Traefik Ingress (k3s-ldn cluster)                 │
│  • Routes: /todo/ → frontend, /todo/api/ → backend          │
└─────────┬───────────────────────┬───────────────────────────┘
          │                       │
          ↓                       ↓
┌─────────────────────┐  ┌─────────────────────┐
│   Frontend Pod      │  │   Backend Pod       │
│  ┌───────────────┐  │  │  ┌───────────────┐  │
│  │  Nginx        │  │  │  │  FastAPI      │  │
│  │  • Serves     │  │  │  │  • REST API   │  │
│  │    React SPA  │  │  │  │  • SSE events │  │
│  │  • SPA routing│  │  │  └───────┬───────┘  │
│  └───────────────┘  │  │          │          │
└─────────────────────┘  └──────────┼──────────┘
                                    │
                                    ↓
                         ┌─────────────────────┐
                         │   Neo4j Pod         │
                         │  • Graph Database   │
                         │  • 1GB Longhorn PVC │
                         └─────────────────────┘
```

## Repository Structure

### Main Repositories

1. **todo-docker-compose** (this repo)
   - Purpose: Docker build orchestration
   - Contains: Dockerfiles, nginx config, deployment scripts
   - Submodules:
     - `backend/repo` → [todo](https://github.com/shiukaheng/todo) (Python/FastAPI)
     - `frontend/repo` → [todo-gui](https://github.com/shiukaheng/todo-gui) (React/Vite)

2. **k3s-ldn-gitops**
   - Purpose: GitOps deployment manifests
   - Contains: Kubernetes YAML files
   - File: `apps/todo/deployment.yaml`
   - Managed by: ArgoCD

### Container Registry
- Docker Hub: `shiukaheng/todo-backend:*`, `shiukaheng/todo-frontend:*`
- Tags: Commit hash (e.g., `140d743`) + `:latest`

## Development Cycle

### 1. Making Code Changes

**Backend changes:**
```bash
cd backend/repo
# Make changes to Python code
git add -A
git commit -m "Description of changes"
git push
```

**Frontend changes:**
```bash
cd frontend/repo
# Make changes to React code
git add -A
git commit -m "Description of changes"
git push
```

### 2. Update Submodule References

After pushing changes to backend/frontend repos:

```bash
# From todo-docker-compose root
cd /mnt/workspace/repos/todo-docker-compose

# Update submodule pointer
git add backend/repo  # or frontend/repo
git commit -m "Update backend submodule: <description>"
git push
```

### 3. Build and Deploy

#### Option A: Automated GitOps Deployment (Recommended)

Use the deployment script:

```bash
./deploy-gitops.sh
```

This script will:
1. ✅ Get current commit hashes from submodules
2. ✅ Build multi-arch images (arm64 + amd64)
3. ✅ Push to Docker Hub with commit hash tags
4. ✅ Update k3s-ldn-gitops repo with new image tags
5. ✅ Trigger ArgoCD sync
6. ✅ Wait for rollout completion

#### Option B: Manual Deployment

If you need more control:

**Build images:**
```bash
# Get commit hashes
BACKEND_COMMIT=$(cd backend/repo && git rev-parse --short HEAD)
FRONTEND_COMMIT=$(cd frontend/repo && git rev-parse --short HEAD)

# Build backend
docker buildx build --platform linux/arm64,linux/amd64 \
  -t shiukaheng/todo-backend:$BACKEND_COMMIT \
  -t shiukaheng/todo-backend:latest \
  --push \
  -f backend/Dockerfile .

# Build frontend (with correct base path!)
docker buildx build --platform linux/arm64,linux/amd64 \
  --build-arg BASE_PATH=/todo/ \
  -t shiukaheng/todo-frontend:$FRONTEND_COMMIT \
  -t shiukaheng/todo-frontend:latest \
  --push \
  -f frontend/Dockerfile .
```

**Update GitOps repo:**
```bash
cd /mnt/workspace/repos/k3s-ldn-gitops

# Update image tags
sed -i "s|shiukaheng/todo-backend:.*|shiukaheng/todo-backend:$BACKEND_COMMIT|" apps/todo/deployment.yaml
sed -i "s|shiukaheng/todo-frontend:.*|shiukaheng/todo-frontend:$FRONTEND_COMMIT|" apps/todo/deployment.yaml

# Commit and push
git add apps/todo/deployment.yaml
git commit -m "Update todo: backend $BACKEND_COMMIT, frontend $FRONTEND_COMMIT"
git push
```

**Trigger deployment:**
```bash
# Force ArgoCD sync (optional - it auto-syncs every 3 minutes)
kubectl patch application todo -n argocd \
  --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# Or manually restart deployments
kubectl rollout restart deployment -n todo backend frontend
kubectl rollout status deployment -n todo backend --timeout=300s
kubectl rollout status deployment -n todo frontend --timeout=300s
```

#### Option C: Images Only (Quick Testing)

For rapid iteration without GitOps updates:

```bash
./deploy-images-only.sh
```

⚠️ **Warning**: This doesn't update the GitOps repo, so Git won't reflect the actual deployed version.

## Important Configuration Details

### Frontend Build Arguments

The frontend **must** be built with `BASE_PATH=/todo/`:

```bash
--build-arg BASE_PATH=/todo/
```

Without this, asset URLs will be incorrect (`/assets/...` instead of `/todo/assets/...`), causing MIME type errors.

### Multi-Architecture Builds

The cluster runs on **ARM64** (Mac Mini), so images must be built for both architectures:

```bash
--platform linux/arm64,linux/amd64
```

Forgetting this causes `exec: no such file or directory` errors.

### Nginx Configuration

`frontend/nginx.conf` serves static files and handles SPA routing:
- Does NOT proxy `/api/` (Traefik handles that)
- Serves from `/usr/share/nginx/html`
- Uses `try_files $uri $uri/ /index.html;` for React Router

## Database Operations

### Backup Neo4j Database

```bash
kubectl exec -n todo deployment/neo4j -- \
  cypher-shell -u neo4j -p todo-password-change-me \
  "MATCH (n) RETURN n" > backup.cypher
```

### Run Migrations

The backend has a migration endpoint:

```bash
curl -X POST http://192.168.1.156/todo/api/init
```

This runs:
- `init_db()` - Create constraints
- `prime_tokens()` - Initialize token system
- `migrate_dependency_ids()` - Fix dependency IDs
- `migrate_to_boolean_graph()` - Convert old schema to Boolean Graph

### Access Neo4j Browser

```bash
kubectl port-forward -n todo deployment/neo4j 7474:7474
# Open http://localhost:7474
# Login: neo4j / todo-password-change-me
```

## Accessing the Application

### Production URLs

- **Web UI**: `http://192.168.1.156/todo/` (via Traefik)
- **API**: `http://192.168.1.156/todo/api/` (via Traefik)
- **Tailscale**: `http://100.x.x.x/todo/` (if configured)

⚠️ **Important**: Always access at `/todo/`, NOT root `/`!

### Direct Service Access (debugging)

```bash
# Port-forward to backend
kubectl port-forward -n todo service/backend 8000:8000
# Access at http://localhost:8000

# Port-forward to frontend
kubectl port-forward -n todo service/frontend 8080:80
# Access at http://localhost:8080
```

## Troubleshooting

### Pod won't start: "exec: no such file or directory"

**Cause**: Image built for wrong architecture (x86_64 instead of ARM64)

**Fix**: Rebuild with `--platform linux/arm64,linux/amd64`

### Frontend shows MIME type errors

**Cause**: Accessing app at wrong URL or built without BASE_PATH

**Fix**:
1. Ensure accessing at `http://<ip>/todo/` (not root `/`)
2. Rebuild frontend with `--build-arg BASE_PATH=/todo/`

### API requests fail with CORS errors

**Cause**: Frontend trying to reach wrong backend URL

**Fix**: Ingress routes `/todo/api/` to backend, so API calls should use relative URLs like `/todo/api/tasks`

### Images not updating after push

**Cause**: Kubernetes doesn't pull `:latest` tags if deployment spec unchanged

**Fix**:
```bash
kubectl rollout restart deployment -n todo backend frontend
```

### ArgoCD not syncing

**Check sync status:**
```bash
kubectl get application -n argocd todo
```

**Force sync:**
```bash
kubectl patch application todo -n argocd \
  --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

### Check pod logs

```bash
# Backend logs
kubectl logs -n todo deployment/backend -f

# Frontend logs (nginx)
kubectl logs -n todo deployment/frontend -f

# Neo4j logs
kubectl logs -n todo deployment/neo4j -f
```

### Database connection issues

**Verify Neo4j is running:**
```bash
kubectl get pods -n todo
```

**Test connection:**
```bash
kubectl exec -n todo deployment/neo4j -- \
  cypher-shell -u neo4j -p todo-password-change-me \
  "RETURN 1"
```

## Quick Reference Commands

```bash
# Check all pods status
kubectl get pods -n todo

# Watch deployments
kubectl get deployments -n todo -w

# Get pod details
kubectl describe pod -n todo <pod-name>

# Shell into backend pod
kubectl exec -it -n todo deployment/backend -- /bin/sh

# View recent events
kubectl get events -n todo --sort-by='.lastTimestamp'

# Check resource usage
kubectl top pods -n todo
```

## Development Best Practices

1. ✅ **Always test locally first** before building images
2. ✅ **Use semantic commit messages** (they become image tags)
3. ✅ **Update submodule pointers** after pushing backend/frontend changes
4. ✅ **Run migrations** after schema changes
5. ✅ **Backup Neo4j** before major changes
6. ✅ **Check pod logs** if deployment fails
7. ✅ **Use GitOps** for production deployments (Option A)
8. ❌ **Don't use `:latest` tags** in GitOps repo (use commit hashes)
9. ❌ **Don't forget `BASE_PATH=/todo/`** when building frontend
10. ❌ **Don't skip multi-arch builds** for ARM64 cluster

## Migration History

- **2026-02-11**: Migrated from Task-based schema to Boolean Graph architecture
  - Added `:Node` label to all nodes
  - Converted `inferred: true` tasks → `:And` gates
  - Removed `inferred` property
  - Added migration to `/init` endpoint

## Related Documentation

- Backend API: See `backend/repo/README.md`
- Frontend: See `frontend/repo/README.md`
- Kubernetes cluster: See `k3s-ldn-gitops/README.md`
- ArgoCD: `https://argocd.example.com` (if applicable)
