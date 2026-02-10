## Backend Implementation Guide - Boolean Graph Migration

## Files Created

1. **models_new.py** - Updated Pydantic models with `node_type` enum
2. **services_new.py** - Updated service layer with label-based node types
3. This guide

## Step-by-Step Integration

### Step 1: Backup Current Database

```bash
# Already done! You have:
# - graph_backup_20260210_133648_clean.cypher
```

### Step 2: Test Migration on Current Data

```bash
# Run migration in Neo4j (dry run - check what would happen)
docker exec -i todo-docker-compose-neo4j-1 cypher-shell -u neo4j -p password <<'EOF'
// Check current state
MATCH (t:Task) RETURN count(t) as total_tasks,
  count(CASE WHEN t.inferred = true THEN 1 END) as inferred_tasks;

// Preview: What would become And gates?
MATCH (t:Task {inferred: true}) RETURN t.id, t.text LIMIT 5;
EOF
```

### Step 3: Run Database Migration

```bash
docker exec -i todo-docker-compose-neo4j-1 cypher-shell -u neo4j -p password <<'EOF'
// 1. Add :Node label to all tasks
MATCH (t:Task) SET t:Node;

// 2. Convert inferred tasks to And gates
MATCH (t:Task {inferred: true})
SET t:And
REMOVE t:Task, t.completed, t.inferred;

// 3. Remove inferred from regular tasks
MATCH (t:Task {inferred: false})
REMOVE t.inferred;

// 4. Update constraints
DROP CONSTRAINT task_id_unique IF EXISTS;
CREATE CONSTRAINT node_id_unique IF NOT EXISTS
FOR (n:Node) REQUIRE n.id IS UNIQUE;

// Verify
MATCH (n:Node) RETURN labels(n) as labels, count(n) as count;
EOF
```

### Step 4: Replace Backend Files

```bash
cd /mnt/workspace/repos/todo-docker-compose/backend/repo/backend/app

# Backup old files
cp models.py models_old.py
cp core/services.py core/services_old.py

# Replace with new files
cp models_new.py models.py
cp core/services_new.py core/services.py

# Restart backend
docker restart todo-docker-compose-backend-1
```

### Step 5: Update routes.py (Minor Changes)

Only need to update variable names for clarity:

```python
# In routes.py, update imports:
from app.models import (
    NodeCreate,  # was TaskCreate
    NodeUpdate,  # was TaskUpdate
    NodeOut,     # was TaskOut
    # ... rest stays the same
)

# Backward compatibility: Keep TaskCreate as alias
TaskCreate = NodeCreate
TaskUpdate = NodeUpdate
TaskOut = NodeOut
```

**OR** just keep using old names (backward compatibility aliases exist in models_new.py)

### Step 6: Test API

```bash
# Get all nodes
curl http://localhost:8000/tasks

# Should return nodes with node_type field:
# {
#   "tasks": {
#     "task-1": {
#       "id": "task-1",
#       "node_type": "Task",
#       "completed": true,
#       ...
#     },
#     "gate-1": {
#       "id": "gate-1",
#       "node_type": "And",
#       "completed": null,
#       ...
#     }
#   }
# }

# Create new And gate
curl -X POST http://localhost:8000/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "id": "my-and-gate",
    "node_type": "And",
    "text": "All prerequisites met"
  }'

# Change node type
curl -X PATCH http://localhost:8000/tasks/my-task \
  -H "Content-Type: application/json" \
  -d '{"node_type": "Or"}'
```

### Step 7: Update /init endpoint

Update routes.py to call new migration:

```python
@router.post("/init", response_model=OperationResult)
async def init_db():
    """Initialize the database schema and run migrations."""
    with get_session() as session:
        session.execute_write(services.init_db)
    with get_session() as session:
        session.execute_write(services.prime_tokens)
    with get_session() as session:
        session.execute_write(services.migrate_dependency_ids)
    # NEW: Run boolean graph migration
    with get_session() as session:
        session.execute_write(services.migrate_to_boolean_graph)
    return OperationResult(success=True, message="Database initialized")
```

## Key Changes Summary

### Models
- `inferred: bool` → `node_type: NodeType` enum
- `calculated_completed` → `calculated_value`
- Backward compatibility aliases provided

### Services
- `Task` → `Node` dataclass (with `node_type` field)
- Read labels from Neo4j: `RETURN n, labels(n) as labels`
- Extract type: `_extract_node_type(labels)`
- Updated `_ENRICHMENT` query to handle all gate types
- Type conversion logic in `update_node()`

### Database
- Labels: `:Node:Task`, `:Node:And`, etc.
- No `inferred` property
- `completed` only on Task nodes
- DEPENDS_ON relationship unchanged

## Rollback Plan

If something goes wrong:

```bash
# 1. Restore old backend files
cd /mnt/workspace/repos/todo-docker-compose/backend/repo/backend/app
cp models_old.py models.py
cp core/services_old.py core/services.py
docker restart todo-docker-compose-backend-1

# 2. Restore database from backup
docker exec todo-docker-compose-neo4j-1 cypher-shell -u neo4j -p password "MATCH (n) DETACH DELETE n"
cat graph_backup_20260210_133648_clean.cypher | docker exec -i todo-docker-compose-neo4j-1 cypher-shell -u neo4j -p password
```

## Notes

- Backward compatibility maintained where possible
- Frontend can gradually adopt new node_type field
- Old endpoint names still work (/tasks, not /nodes)
- Migration is one-way (inferred flag removed from DB)
