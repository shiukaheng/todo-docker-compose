#!/bin/bash
set -e

# Parse arguments
SKIP_NEO4J=false
for arg in "$@"; do
    case $arg in
        --skip-neo4j|--existing-neo4j)
            SKIP_NEO4J=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-neo4j, --existing-neo4j    Use existing Neo4j instance instead of starting Docker container"
            echo "  -h, --help                        Show this help message"
            exit 0
            ;;
    esac
done

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
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

# Check if Neo4j is already accessible on port 7687
check_neo4j() {
    if command -v nc &> /dev/null; then
        nc -z localhost 7687 2>/dev/null
    elif command -v timeout &> /dev/null; then
        timeout 1 bash -c "</dev/tcp/localhost/7687" 2>/dev/null
    else
        # Fallback: just return success
        return 0
    fi
}

# Start Neo4j in Docker if not already running
if [ "$SKIP_NEO4J" = true ]; then
    echo -e "${YELLOW}Skipping Neo4j startup (using existing instance)${NC}"
    if ! check_neo4j; then
        echo -e "${RED}Warning: Cannot connect to Neo4j on port 7687${NC}"
    fi
else
    echo -e "${BLUE}Checking Neo4j...${NC}"
    if check_neo4j; then
        echo -e "${GREEN}Neo4j already accessible on port 7687 (using existing instance)${NC}"
    elif docker ps | grep -q neo4j-dev; then
        echo -e "${GREEN}Neo4j container already running${NC}"
    else
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
    fi
fi

# Check if port is in use
check_port() {
    lsof -i :$1 >/dev/null 2>&1 || ss -tln | grep -q ":$1 " 2>/dev/null
}

# Check all required ports
echo -e "${BLUE}Checking ports...${NC}"
PORTS_IN_USE=()

if check_port 8000; then
    PORTS_IN_USE+=("8000 (backend)")
fi

if check_port 3000; then
    echo -e "${YELLOW}Warning: Port 3000 (frontend) is in use - Vite will auto-select another port${NC}"
fi

if [ "$SKIP_NEO4J" != true ]; then
    if check_port 7474; then
        PORTS_IN_USE+=("7474 (Neo4j HTTP)")
    fi
    if check_port 7687; then
        PORTS_IN_USE+=("7687 (Neo4j Bolt)")
    fi
fi

if [ ${#PORTS_IN_USE[@]} -gt 0 ]; then
    echo -e "${RED}Error: The following ports are already in use:${NC}"
    for port in "${PORTS_IN_USE[@]}"; do
        echo -e "${RED}  - $port${NC}"
    done
    echo -e "\n${YELLOW}To kill processes using these ports:${NC}"
    echo -e "${YELLOW}  sudo lsof -ti:8000,7474,7687 | xargs kill -9${NC}"
    echo -e "\n${YELLOW}Or check what's using them:${NC}"
    echo -e "${YELLOW}  sudo lsof -i :8000 -i :7474 -i :7687${NC}"
    exit 1
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
echo -e "${GREEN}Backend started (PID: $BACKEND_PID)${NC}"

# Start frontend
echo -e "${BLUE}Starting frontend...${NC}"
cd ../../../frontend/repo
npm install
npm run dev &
FRONTEND_PID=$!
echo -e "${GREEN}Frontend started (PID: $FRONTEND_PID)${NC}"

echo -e "\n${GREEN}✓ Development environment ready!${NC}"
echo -e "${YELLOW}Check the output above for actual URLs (ports may vary if defaults are in use)${NC}"
echo -e "\nPress Ctrl+C to stop all services\n"

# Wait for processes
wait
