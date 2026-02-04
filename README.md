# Todo Docker Compose

Docker Compose setup for the Todo application stack:
- **Neo4j** - Graph database
- **Backend** - FastAPI server
- **Frontend** - Web UI

## Quick Start

1. Clone with submodules:
   ```bash
   git clone --recurse-submodules https://github.com/shiukaheng/todo-docker-compose.git
   cd todo-docker-compose
   ```

2. Copy and configure environment:
   ```bash
   cp .env.example .env
   # Edit .env as needed
   ```

3. Start all services:
   ```bash
   docker-compose up -d
   ```

4. Access the app:
   - Frontend: http://localhost:3000
   - Backend API: http://localhost:8000
   - Neo4j Browser: http://localhost:7474

## Development Mode

For development with hot reloading:

```bash
docker-compose -f docker-compose.dev.yml up
```

This mounts source code from submodules and runs:
- **Frontend**: Vite dev server with hot reload
- **Backend**: Uvicorn with `--reload`

Changes to source files are reflected immediately.

## Configuration

All configuration is done via environment variables in `.env`:

### Neo4j
| Variable | Default | Description |
|----------|---------|-------------|
| `NEO4J_USER` | `neo4j` | Neo4j username |
| `NEO4J_PASSWORD` | `password` | Neo4j password |
| `NEO4J_HTTP_PORT` | `7474` | Neo4j browser port |
| `NEO4J_BOLT_PORT` | `7687` | Neo4j bolt protocol port |

### Backend
| Variable | Default | Description |
|----------|---------|-------------|
| `BACKEND_PORT` | `8000` | API server port |

### Frontend
| Variable | Default | Description |
|----------|---------|-------------|
| `FRONTEND_PORT` | `3000` | Web UI port |
| `API_URL` | `http://localhost:8000` | Backend API URL (injected at runtime) |

## Submodules

To update submodules to latest:
```bash
git submodule update --remote
```

To rebuild after changes:
```bash
docker-compose build
docker-compose up -d
```

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Frontend  │────▶│   Backend   │────▶│    Neo4j    │
│  (nginx)    │     │  (FastAPI)  │     │  (database) │
│   :3000     │     │    :8000    │     │    :7687    │
└─────────────┘     └─────────────┘     └─────────────┘
```
