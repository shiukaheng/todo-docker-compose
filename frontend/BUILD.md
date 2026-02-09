# Frontend Build Configuration

## Base Path Configuration

The frontend build supports configurable base paths, allowing deployment at any URL prefix.

### For Development (root path)

```bash
npm run dev
# Runs at http://localhost:3000/
```

Or explicitly set:
```bash
BASE_PATH=/ npm run build
```

### For Production (custom path)

Build with a specific base path using the `BASE_PATH` environment variable:

```bash
# Build for /todo/ deployment
BASE_PATH=/todo/ npm run build

# Build for /app/ deployment  
BASE_PATH=/app/ npm run build

# Build for /my-custom-path/ deployment
BASE_PATH=/my-custom-path/ npm run build
```

### Docker Build

Use the `BASE_PATH` build argument:

```bash
# For /todo/ deployment
docker build --build-arg BASE_PATH=/todo/ -t my-frontend .

# For root deployment (default)
docker build -t my-frontend .

# Multi-arch build for production
docker buildx build --platform linux/amd64,linux/arm64 \
  --build-arg BASE_PATH=/todo/ \
  -t shiukaheng/todo-frontend:latest \
  --push .
```

### How It Works

- The `BASE_PATH` environment variable is read by `vite.config.ts`
- Default value: `/` (root deployment)
- Vite uses this to prefix all asset paths in the built HTML
- The runtime API URL is still injected via `API_URL` environment variable at container startup
