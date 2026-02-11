# Todo App

Boolean graph-based todo application with recursive task dependencies.

## Architecture

```
User → Traefik Ingress → Frontend (React + Nginx) → Backend (FastAPI) → Neo4j
```

- **Frontend**: React SPA with graph visualization
- **Backend**: FastAPI with SSE for real-time updates
- **Database**: Neo4j graph database

## Quick Start

### Deployment

Deploy to Kubernetes cluster:

```bash
./scripts/deploy-gitops.sh
```

See [docs/deployment.md](docs/deployment.md) for detailed deployment guide.

### Development

Run development environment:

```bash
./scripts/dev.sh
```

## Repository Structure

```
.
├── README.md
├── scripts/           # Deployment scripts
│   ├── deploy-gitops.sh
│   ├── deploy-images-only.sh
│   └── dev.sh
├── docs/              # Documentation
│   ├── deployment.md   # Deployment guide
│   ├── schema.md       # Boolean graph schema
│   ├── properties.md   # Node properties reference
│   └── publishing.md   # Client library publishing
├── backend/
│   ├── Dockerfile
│   └── repo/          # Git submodule → shiukaheng/todo
├── frontend/
│   ├── Dockerfile
│   ├── nginx.conf
│   └── repo/          # Git submodule → shiukaheng/todo-gui
└── docker-compose.yml
```

## Submodules

This repo uses git submodules for backend and frontend code:

**Update submodules:**
```bash
git submodule update --remote
```

**Clone with submodules:**
```bash
git clone --recurse-submodules https://github.com/shiukaheng/todo-docker-compose.git
```

## Documentation

- **[Deployment Guide](docs/deployment.md)** - How to deploy and develop
- **[Schema Reference](docs/schema.md)** - Boolean graph architecture
- **[Properties Reference](docs/properties.md)** - Node properties and fields
- **[Publishing Guide](docs/publishing.md)** - How to publish the API client

## License

MIT
