# Migration Guide: Boolean Graph Implementation

**Version:** 1.0.0
**Date:** 2026-02-10
**Status:** Ready for deployment

## Overview

This guide explains how to migrate from the old Task-based schema with `inferred` flags to the new Boolean Graph schema with explicit gate types.

## What's Changed

### Database Schema

**Old Schema:**
```cypher
(:Task {
  inferred: boolean,  // Implicit AND gate
  completed: boolean
})
```

**New Schema:**
```cypher
(:Node:Task { completed: boolean })
(:Node:And)
(:Node:Or)
(:Node:Not)
(:Node:ExactlyOne)
```

### API Response Format

**Old Response:**
```json
{
  "id": "task-1",
  "inferred": false,
  "completed": true,
  "calculatedCompleted": true
}
```

**New Response:**
```json
{
  "id": "task-1",
  "node_type": "Task",
  "completed": true,
  "calculated_value": true,
  "deps_clear": true,
  "is_actionable": false
}
```

### Semantic Changes

**Key Formula:** `calculated_value = own_value AND deps_clear`

| Property | Old Behavior | New Behavior |
|----------|-------------|--------------|
| `completed` | Task completion flag | Task completion flag (unchanged) |
| `inferred` | Boolean flag for AND gates | **REMOVED** - replaced by `node_type` |
| `calculatedCompleted` | Computed value | **RENAMED** to `calculated_value` |
| `deps_clear` | Not exposed | **NEW** - gate-specific dependency evaluation |
| `is_actionable` | Frontend computed | **NEW** - backend computed |

## Migration Steps

### Step 1: Backup Current Database

```bash
# Run from project root
./backup_graph.sh

# Or manually:
docker exec todo-docker-compose-neo4j-1 cypher-shell -u neo4j -p password \
  "MATCH (n) OPTIONAL MATCH (n)-[r]->(m) RETURN n, r, m" --format plain \
  > graph_backup_$(date +%Y%m%d_%H%M%S).cypher
```

**⚠️ CRITICAL:** Verify backup exists before proceeding!

### Step 2: Run Database Migration

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

// 5. Ensure all DEPENDS_ON relationships have IDs
MATCH (a:Node)-[r:DEPENDS_ON]->(b:Node)
WHERE r.id IS NULL
SET r.id = randomUUID();

// 6. Verify migration
MATCH (n:Node)
RETURN labels(n) as node_type, count(n) as count
ORDER BY node_type;
EOF
```

**Expected Output:**
```
node_type           | count
--------------------|------
["Node","Task"]     | XX
["Node","And"]      | YY
```

### Step 3: Update Backend Code

```bash
cd backend/repo/backend/app

# Backup old files (optional but recommended)
cp models.py models_old.py
cp core/services.py core/services_old.py

# Replace with new implementation
mv models_new.py models.py
mv core/services_new.py core/services.py

# Restart backend container
cd /mnt/workspace/repos/todo-docker-compose
docker-compose restart backend
```

### Step 4: Verify Backend

```bash
# Test API is responding
curl http://localhost:8000/tasks | jq '.tasks | keys | length'

# Should return number of nodes

# Verify new fields exist
curl http://localhost:8000/tasks | jq '.tasks | to_entries[0].value | keys'

# Should include: "node_type", "calculated_value", "deps_clear", "is_actionable"
```

### Step 5: Update Frontend (If Applicable)

See `FRONTEND_UPDATES_NEEDED.md` for detailed changes. Summary:

1. **Property Renames:**
   ```typescript
   // OLD
   const isComplete = node.calculatedCompleted;
   const isInferred = node.inferred;

   // NEW
   const isComplete = node.calculated_value;
   const nodeType = node.node_type;
   ```

2. **Shape Mapping:**
   ```typescript
   // OLD
   const shape = node.inferred ? 'upTriangle' : 'square';

   // NEW
   const shape = {
     'Task': 'square',
     'And': 'upTriangle',
     'Or': 'diamond',
     'Not': 'downTriangle',
     'ExactlyOne': 'hexagon'
   }[node.node_type] || 'square';
   ```

3. **Actionability:**
   ```typescript
   // OLD (manually computed)
   const isBlocked = childTaskIds.some(id => !taskCalcCompleted.get(id));
   const isActionable = !isBlocked && !node.completed;

   // NEW (backend provides)
   const isActionable = node.is_actionable;
   ```

## Breaking Changes

### 1. API Response Fields

| Field | Change | Impact |
|-------|--------|--------|
| `inferred` | **REMOVED** | Must use `node_type` instead |
| `calculatedCompleted` | **RENAMED** to `calculated_value` | Update all references |
| `deps_clear` | **ADDED** | New field (optional to use) |
| `is_actionable` | **ADDED** | New field (optional to use) |

### 2. Node Types

Old behavior:
- Regular tasks: `{inferred: false}`
- AND gates: `{inferred: true}`

New behavior:
- Tasks: `{node_type: "Task"}`
- AND gates: `{node_type: "And"}`
- OR gates: `{node_type: "Or"}`
- NOT gates: `{node_type: "Not"}`
- XOR gates: `{node_type: "ExactlyOne"}`

### 3. Task Completion Semantics

**Old:** Task `completed=true` → always shows as complete

**New:** Task `completed=true` but `deps_clear=false` → shows as incomplete

This enforces logical consistency: you can't complete a task if prerequisites aren't met.

## Compatibility

### Backend Compatibility

The new backend provides backward compatibility aliases:
```python
# These work but are deprecated
TaskCreate = NodeCreate
TaskUpdate = NodeUpdate
TaskOut = NodeOut
```

### Frontend Compatibility

During transition, support both:
```typescript
const nodeType = data.node_type || (data.inferred ? "And" : "Task");
const value = data.calculated_value ?? data.calculatedCompleted;
```

## Rollback Plan

If migration fails:

```bash
# 1. Restore old backend files
cd backend/repo/backend/app
mv models_old.py models.py
mv core/services_old.py core/services.py
docker-compose restart backend

# 2. Restore database from backup
docker exec todo-docker-compose-neo4j-1 cypher-shell -u neo4j -p password \
  "MATCH (n) DETACH DELETE n"
./restore_graph.sh graph_backup_YYYYMMDD_HHMMSS.cypher
```

## Testing After Migration

### 1. Test Basic Operations

```bash
# Create a Task
curl -X POST http://localhost:8000/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "id": "test-task",
    "node_type": "Task",
    "text": "Test task",
    "completed": false
  }'

# Verify it has correct fields
curl http://localhost:8000/tasks/test-task | jq '{
  node_type,
  completed,
  calculated_value,
  deps_clear,
  is_actionable
}'
```

### 2. Test Gate Creation

```bash
# Create an Or gate
curl -X POST http://localhost:8000/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "id": "test-or-gate",
    "node_type": "Or",
    "text": "Test OR gate"
  }'

# Verify it has node_type: "Or" and completed: null
curl http://localhost:8000/tasks/test-or-gate | jq '{
  node_type,
  completed,
  calculated_value
}'
```

### 3. Test Dependency Logic

```bash
# Create task with dependency
curl -X POST http://localhost:8000/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "id": "dependent-task",
    "node_type": "Task",
    "text": "Depends on test-task",
    "completed": false,
    "depends": ["test-task"]
  }'

# Check deps_clear and is_actionable
curl http://localhost:8000/tasks/dependent-task | jq '{
  completed,
  deps_clear,
  is_actionable,
  calculated_value
}'

# Expected: deps_clear=false, is_actionable=false (test-task not complete)
```

### 4. Test Task Completion Logic

```bash
# Complete the dependency
curl -X PATCH http://localhost:8000/tasks/test-task \
  -H "Content-Type: application/json" \
  -d '{"completed": true}'

# Re-check dependent task
curl http://localhost:8000/tasks/dependent-task | jq '{
  completed,
  deps_clear,
  is_actionable,
  calculated_value
}'

# Expected: deps_clear=true, is_actionable=true (can work on it now)
```

## Common Issues

### Issue 1: Inferred Tasks Not Converted

**Symptom:** Tasks still have `inferred` property

**Fix:**
```bash
# Re-run migration step 2
docker exec -i todo-docker-compose-neo4j-1 cypher-shell -u neo4j -p password <<'EOF'
MATCH (t:Task)
WHERE t.inferred IS NOT NULL
REMOVE t.inferred;
EOF
```

### Issue 2: Frontend Shows Wrong Shapes

**Symptom:** All nodes show as squares

**Cause:** Frontend still using `inferred` flag

**Fix:** Update frontend to use `node_type` (see FRONTEND_UPDATES_NEEDED.md)

### Issue 3: Backend Returns 500 Errors

**Symptom:** API calls fail after migration

**Cause:** Likely database constraint issues

**Fix:**
```bash
# Check constraints
docker exec -i todo-docker-compose-neo4j-1 cypher-shell -u neo4j -p password \
  "SHOW CONSTRAINTS"

# Re-create constraint if missing
docker exec -i todo-docker-compose-neo4j-1 cypher-shell -u neo4j -p password \
  "CREATE CONSTRAINT node_id_unique IF NOT EXISTS FOR (n:Node) REQUIRE n.id IS UNIQUE"
```

## Performance Considerations

### Calculation Overhead

The new backend calculates additional properties:
- `calculated_value` (recursive with memoization)
- `deps_clear` (gate-specific logic)
- `is_actionable` (simple boolean)
- `calculated_due` (recursive with memoization)

**Impact:** Negligible for graphs <1000 nodes. Memoization ensures O(V+E) complexity.

### Database Query Changes

Old schema queried `inferred` property. New schema uses labels:
```cypher
// OLD
MATCH (t:Task {inferred: false})

// NEW
MATCH (t:Task)  // Task label = not a gate
```

**Impact:** Label-based queries are typically faster than property queries.

## Migration Checklist

- [ ] Backup database (verify backup exists)
- [ ] Run database migration (all 6 steps)
- [ ] Verify migration (check node counts and labels)
- [ ] Backup old backend files
- [ ] Replace backend models.py and services.py
- [ ] Restart backend container
- [ ] Test API endpoints (verify new fields)
- [ ] Update frontend (if applicable)
- [ ] Test end-to-end functionality
- [ ] Monitor for errors in production
- [ ] Remove backup files after 7 days of stable operation

## Support

For issues or questions:
1. Check `WATERTIGHTNESS_REVIEW.md` for implementation verification
2. See `NODE_PROPERTIES_REFERENCE.md` for property semantics
3. Review `BOOLEAN_GRAPH_SCHEMA.md` for schema details
4. Consult `DEPLOYMENT_READY_SUMMARY.md` for deployment examples

## Migration Timeline Estimate

| Task | Time Estimate |
|------|---------------|
| Backup database | 2-5 minutes |
| Run migration | 1-3 minutes |
| Update backend | 2-5 minutes |
| Test backend | 5-10 minutes |
| Update frontend | 30-60 minutes |
| End-to-end testing | 15-30 minutes |
| **Total** | **~1-2 hours** |

*Times assume small-medium graph (<100 nodes) and single developer.*

## Post-Migration

After successful migration:

1. **Monitor logs** for 24 hours
2. **Keep backups** for at least 7 days
3. **Document any custom changes** made during migration
4. **Update team documentation** with new API format
5. **Remove old backup files** after stability confirmed

## Version Compatibility

| Component | Old Version | New Version | Compatible? |
|-----------|-------------|-------------|-------------|
| Neo4j | 5.x | 5.x | ✅ Yes |
| Backend Python | 3.11+ | 3.11+ | ✅ Yes |
| Pydantic | 2.x | 2.x | ✅ Yes |
| Frontend API calls | Old format | New format | ⚠️ Needs update |

---

**Last Updated:** 2026-02-10
**Migration Version:** 1.0.0
