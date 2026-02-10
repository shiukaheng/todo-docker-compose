# Backend API Migration for Boolean Logic Graph

## Current API Analysis

**Current Schema:**
- Single `:Task` label
- `inferred: bool` toggles AND-gate behavior
- `DEPENDS_ON` relationship (from_id depends on to_id)

**Current Endpoints:**
- `GET /tasks` - list all tasks
- `GET /tasks/{id}` - get single task
- `POST /tasks` - create task with `inferred` flag
- `PATCH /tasks/{id}` - update task (can toggle `inferred`)
- `DELETE /tasks/{id}` - delete task
- `POST /links` - create DEPENDS_ON relationship
- `DELETE /links` - remove DEPENDS_ON relationship

## Proposed Changes

### 1. Data Model Updates

**Add `node_type` field (replaces `inferred`):**

```python
# models.py
from enum import Enum

class NodeType(str, Enum):
    TASK = "Task"
    AND = "And"
    OR = "Or"
    NOT = "Not"
    EXACTLY_ONE = "ExactlyOne"

class TaskBase(BaseModel):
    text: str | None = None
    completed: bool = False  # Only used for Task nodes
    node_type: NodeType = NodeType.TASK  # NEW
    due: int | None = None
    # REMOVED: inferred field

class TaskCreate(TaskBase):
    id: str
    depends: list[str] | None = None
    blocks: list[str] | None = None

class TaskUpdate(BaseModel):
    text: str | None = None
    completed: bool | None = None  # Ignored for gate nodes
    node_type: NodeType | None = None  # NEW: can change type
    due: int | None = None
    # REMOVED: inferred field

class TaskOut(BaseModel):
    id: str
    text: str
    node_type: NodeType  # NEW
    completed: bool | None  # None for gate nodes
    due: int | None
    created_at: int | None
    updated_at: int | None
    calculated_value: bool | None  # NEW: renamed from calculated_completed
    calculated_due: int | None
    deps_clear: bool | None
    parents: list[str]
    children: list[str]
```

### 2. Database Schema Changes

**Node labels:**
```cypher
// Before
(:Task {id, text, completed, inferred, due, created_at, updated_at})

// After
(:Node:Task {id, text, completed, due, created_at, updated_at})
(:Node:And {id, text, due, created_at, updated_at})
(:Node:Or {id, text, due, created_at, updated_at})
(:Node:Not {id, text, due, created_at, updated_at})
(:Node:ExactlyOne {id, text, due, created_at, updated_at})
```

**Relationships:**
```cypher
// Before
(Task)-[:DEPENDS_ON {id}]->(Task)

// After
(Gate)-[:INPUT {id, created_at}]->(Node)
```

### 3. Service Layer Updates

**services.py changes:**

```python
@dataclass
class Node:
    """Node data (any type)."""
    id: str
    node_type: str  # "Task", "And", "Or", "Not", "ExactlyOne"
    text: str = ""
    completed: bool | None = None  # Only for Task nodes
    due: int | None = None
    created_at: int | None = None
    updated_at: int | None = None

@dataclass
class EnrichedNode:
    """Node with calculated properties."""
    node: Node
    calculated_value: bool | None = None  # Renamed from calculated_completed
    calculated_due: int | None = None
    deps_clear: bool | None = None

# Updated enrichment query
_ENRICHMENT = """
    OPTIONAL MATCH (n)-[:INPUT]->(input)
    WITH n,
         collect(DISTINCT input) AS all_inputs,
         // ... calculate based on node_type
    RETURN n,
           CASE
             WHEN n:Task THEN n.completed
             WHEN n:And THEN (size(all_inputs) = 0 OR all(i IN all_inputs WHERE ...))
             WHEN n:Or THEN size([i IN all_inputs WHERE ...]) > 0
             WHEN n:Not THEN size([i IN all_inputs WHERE ...]) = 0
             WHEN n:ExactlyOne THEN size([i IN all_inputs WHERE ...]) = 1
           END AS calculated_value,
           // ... calculated_due and deps_clear
"""

def add_node(
    tx,
    id: str,
    node_type: str = "Task",
    text: str | None = None,
    completed: bool = False,
    due: int | None = None,
    depends: list[str] | None = None,
    blocks: list[str] | None = None,
) -> Node:
    """Create a new node of any type."""
    now = int(time.time())
    props = {
        "id": id,
        "created_at": now,
        "updated_at": now,
    }
    if text is not None:
        props["text"] = text
    if due is not None:
        props["due"] = due
    if node_type == "Task":
        props["completed"] = completed

    # Create with appropriate labels
    labels = f":Node:{node_type}"
    tx.run(f"CREATE (n{labels} $props)", props=props)

    # Create INPUT relationships
    for dep_id in (depends or []):
        _create_input(tx, id, dep_id)
    for block_id in (blocks or []):
        _create_input(tx, block_id, id)

    return Node(node_type=node_type, **props)

def update_node(
    tx,
    id: str,
    node_type: str | None = None,
    text: str | None = None,
    completed: bool | None = None,
    due: int | None = None,
) -> bool:
    """Update an existing node."""
    # If changing type, need to:
    # 1. Remove old type label
    # 2. Add new type label
    # 3. Handle completed property (add/remove)

    if node_type is not None:
        # Get current type
        result = tx.run("MATCH (n:Node {id: $id}) RETURN labels(n) AS labels", id=id)
        record = result.single()
        if not record:
            return False

        current_labels = record["labels"]
        current_type = next((l for l in current_labels if l in ["Task", "And", "Or", "Not", "ExactlyOne"]), None)

        if current_type and current_type != node_type:
            # Change type
            tx.run(
                f"MATCH (n:{current_type} {{id: $id}}) "
                f"REMOVE n:{current_type} "
                f"SET n:{node_type}, n.updated_at = $now "
                # Add completed if converting TO Task
                + ("SET n.completed = false " if node_type == "Task" and current_type != "Task" else "")
                # Remove completed if converting FROM Task
                + ("REMOVE n.completed " if current_type == "Task" and node_type != "Task" else ""),
                id=id, now=int(time.time())
            )

    # Update other properties
    props = {}
    if text is not None:
        props["text"] = text
    if completed is not None:
        props["completed"] = completed
    if due is not None:
        props["due"] = due

    if props:
        props["updated_at"] = int(time.time())
        result = tx.run(
            "MATCH (n:Node {id: $id}) SET n += $props RETURN n",
            id=id, props=props
        )
        return result.single() is not None

    return True

def _create_input(tx, from_id: str, to_id: str) -> str:
    """Create INPUT relationship. Returns relationship ID."""
    if from_id == to_id:
        raise ValueError(f"Self-loop not allowed: {from_id}")

    dep_id = str(uuid.uuid4())
    result = tx.run(
        "MATCH (a:Node {id: $from_id}), (b:Node {id: $to_id}) "
        "MERGE (a)-[r:INPUT]->(b) "
        "ON CREATE SET r.id = $dep_id, r.created_at = $now "
        "RETURN r.id AS dep_id",
        from_id=from_id, to_id=to_id, dep_id=dep_id, now=int(time.time())
    )
    record = result.single()
    if not record:
        raise ValueError(f"Node not found: {from_id} or {to_id}")
    return record["dep_id"]
```

### 4. Migration Strategy

**Option A: Backward Compatible (Recommended)**
- Keep `inferred` field in API for now (deprecated)
- Map `inferred=true` → `node_type="And"`
- Map `inferred=false` → `node_type="Task"`
- Frontend can gradually migrate to use `node_type`

**Option B: Breaking Change**
- Remove `inferred` field immediately
- Require frontend to use `node_type`
- Run migration script on existing data

### 5. Migration Script

```cypher
// 1. Add :Node label to all tasks
MATCH (t:Task)
SET t:Node;

// 2. Convert inferred tasks to And gates
MATCH (t:Task)
WHERE t.inferred = true
SET t:And
REMOVE t:Task, t.completed, t.inferred;

// 3. Remove inferred from regular tasks
MATCH (t:Task)
WHERE t.inferred = false
REMOVE t.inferred;

// 4. Rename DEPENDS_ON to INPUT
MATCH (a)-[r:DEPENDS_ON]->(b)
CREATE (a)-[:INPUT {id: r.id, created_at: null}]->(b)
DELETE r;

// 5. Update constraint
DROP CONSTRAINT task_id_unique IF EXISTS;
CREATE CONSTRAINT node_id_unique IF NOT EXISTS
FOR (n:Node) REQUIRE n.id IS UNIQUE;
```

### 6. API Endpoint Changes

**No breaking changes to endpoints:**
- `GET /tasks` → `GET /tasks` (same, returns all nodes)
- `POST /tasks` → `POST /tasks` (accepts `node_type` instead of `inferred`)
- `PATCH /tasks/{id}` → `PATCH /tasks/{id}` (can change `node_type`)
- `POST /links` → `POST /links` (creates INPUT instead of DEPENDS_ON)

**Optional: Add type-conversion endpoint:**
```python
@router.post("/tasks/{task_id}/convert", response_model=OperationResult)
async def convert_node_type(task_id: str, new_type: NodeType):
    """Convert a node to a different type."""
    # Validates constraints (e.g., can't convert Task with inputs to another type)
    ...
```

### 7. Validation Rules

**Type-specific validations:**
- Task nodes: must have `completed` property, should NOT have INPUT relationships
- Gate nodes: must NOT have `completed` property, CAN have INPUT relationships
- Not gate: works with any number of inputs (NOR behavior)
- ExactlyOne gate: semantically needs ≥2 inputs but technically allows 0-∞

### 8. Calculated Value Logic

**Updated logic for different node types:**

```python
def calculate_node_value(node: Node, inputs: list[Node]) -> bool:
    """Calculate boolean value for a node."""
    if node.node_type == "Task":
        return node.completed

    input_values = [calculate_node_value(inp, ...) for inp in inputs]

    if node.node_type == "And":
        return len(input_values) == 0 or all(input_values)  # vacuous truth
    elif node.node_type == "Or":
        return len(input_values) > 0 and any(input_values)  # vacuous false
    elif node.node_type == "Not":
        return not any(input_values)  # NOR behavior
    elif node.node_type == "ExactlyOne":
        return sum(input_values) == 1

    return False
```

## Summary

**Key Changes:**
1. Add `node_type: NodeType` field (replaces `inferred`)
2. Change `DEPENDS_ON` → `INPUT` relationship
3. Add `:Node` label to all nodes
4. Use specific labels for types (`:Task`, `:And`, `:Or`, `:Not`, `:ExactlyOne`)
5. `completed` only exists on Task nodes
6. Rename `calculated_completed` → `calculated_value` (more general)

**Backward Compatibility:**
- Option to keep `inferred` in API layer (map to node_type)
- PATCH endpoint can change node type
- Minimal frontend changes needed

**Migration Effort:**
- Database: Run migration script (5 Cypher queries)
- Backend: Update models, services (1-2 days)
- Frontend: Minimal if using backward-compatible approach
