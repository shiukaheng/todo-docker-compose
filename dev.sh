#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}Starting development environment...${NC}"

# Function to cleanup on exit
cleanup() {
    echo -e "\n${RED}Shutting down...${NC}"
    if [ -n "$BACKEND_PID" ]; then
        kill $BACKEND_PID 2>/dev/null || true
    fi
    if [ -n "$FRONTEND_PID" ]; then
        kill $FRONTEND_PID 2>/dev/null || true
    fi
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# Start Neo4j in Docker if not already running
echo -e "${BLUE}Checking Neo4j...${NC}"
if ! docker ps | grep -q neo4j-dev; then
    echo -e "${GREEN}Starting Neo4j container...${NC}"
    docker run -d \
        --name neo4j-dev \
        -p 7474:7474 \
        -p 7687:7687 \
        -e NEO4J_AUTH=neo4j/password \
        --rm \
        neo4j:5
    echo -e "${GREEN}Waiting for Neo4j to be ready...${NC}"
    sleep 10
else
    echo -e "${GREEN}Neo4j already running${NC}"
fi

# Start backend with uv
echo -e "${BLUE}Starting backend...${NC}"
cd backend/repo/backend
if ! command -v uv &> /dev/null; then
    echo -e "${RED}uv not found. Install it with: curl -LsSf https://astral.sh/uv/install.sh | sh${NC}"
    exit 1
fi

uv sync
NEO4J_URL=bolt://localhost:7687 \
NEO4J_USER=neo4j \
NEO4J_PASSWORD=password \
uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000 &
BACKEND_PID=$!
echo -e "${GREEN}Backend started (PID: $BACKEND_PID) on http://localhost:8000${NC}"

# Start frontend
echo -e "${BLUE}Starting frontend...${NC}"
cd ../../../frontend/repo
npm install
npm run dev &
FRONTEND_PID=$!
echo -e "${GREEN}Frontend started (PID: $FRONTEND_PID) on http://localhost:3000${NC}"

echo -e "\n${GREEN}✓ Development environment ready!${NC}"
echo -e "${BLUE}  Frontend: http://localhost:3000${NC}"
echo -e "${BLUE}  Backend:  http://localhost:8000${NC}"
echo -e "${BLUE}  Neo4j:    http://localhost:7474${NC}"
echo -e "\nPress Ctrl+C to stop all services\n"

# Wait for processes
wait
