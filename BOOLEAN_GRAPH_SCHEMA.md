# Boolean Logic Graph Schema

## Overview

A universal boolean function graph where tasks and logic gates combine to express complex completion dependencies.

## Node Types

**Type is stored in LABELS only** - no `node_type` property.

All nodes have:
- `:Node` label (for unified querying)
- Type-specific label (`:Task`, `:And`, `:Or`, `:Not`, `:ExactlyOne`)

### Task Node
```cypher
(:Node:Task {
  id: string,              // Unique identifier (REQUIRED)
  text: string | null,     // Human-readable description
  completed: boolean,      // Manual completion flag (REQUIRED, default: false)
  due: int | null,         // Due date (unix timestamp)
  created_at: int,         // Creation timestamp (REQUIRED)
  updated_at: int          // Last update timestamp (REQUIRED)
})
```

**Semantics:**
- **Tasks CAN have dependencies** (not leaf nodes!)
- Value = `completed` property (manual flag)
- Dependencies are ANDed: Task is **actionable** when all deps satisfied
- `deps_clear = true` means dependencies satisfied (task can be worked on)
- User manually marks complete/incomplete

### And Gate
```cypher
(:Node:And {
  id: string,              // Unique identifier (REQUIRED)
  text: string | null,     // Human-readable description
  due: int | null,         // Due date (unix timestamp)
  created_at: int,         // Creation timestamp (REQUIRED)
  updated_at: int          // Last update timestamp (REQUIRED)
})
```

**Semantics:**
- Value = `all(inputs.value == true)`
- 0 inputs: `true` (vacuous truth - empty AND)
- 1 input: pass-through (identity)
- N inputs: ALL must be complete
- No `completed` property (computed)

### Or Gate
```cypher
(:Node:Or {
  id: string,              // Unique identifier (REQUIRED)
  text: string | null,     // Human-readable description
  due: int | null,         // Due date (unix timestamp)
  created_at: int,         // Creation timestamp (REQUIRED)
  updated_at: int          // Last update timestamp (REQUIRED)
})
```

**Semantics:**
- Value = `any(inputs.value == true)`
- 0 inputs: `false` (vacuous - empty OR)
- 1 input: pass-through (identity)
- N inputs: ANY must be complete
- No `completed` property (computed)

### Not Gate
```cypher
(:Node:Not {
  id: string,              // Unique identifier (REQUIRED)
  text: string | null,     // Human-readable description
  due: int | null,         // Due date (unix timestamp)
  created_at: int,         // Creation timestamp (REQUIRED)
  updated_at: int          // Last update timestamp (REQUIRED)
})
```

**Semantics:**
- Value = `!(input1 OR input2 OR ... OR inputN)` (NOR)
- 0 inputs: `true` (NOT of nothing = true)
- 1 input: simple inversion `!input`
- N inputs: true when NONE are complete
- No `completed` property (computed)

**Use cases:**
- "No blockers" - true when all blocker tasks incomplete
- "Bug-free" - true when all bug tasks incomplete

### ExactlyOne Gate
```cypher
(:Node:ExactlyOne {
  id: string,              // Unique identifier (REQUIRED)
  text: string | null,     // Human-readable description
  due: int | null,         // Due date (unix timestamp)
  created_at: int,         // Creation timestamp (REQUIRED)
  updated_at: int          // Last update timestamp (REQUIRED)
})
```

**Semantics:**
- Value = `count(inputs.value == true) == 1`
- 0 inputs: `false` (zero complete ≠ one complete)
- 1 input: pass-through (if complete, then exactly one is complete)
- N inputs: EXACTLY ONE must be complete
- No `completed` property (computed)

**Use cases:**
- "Choose approach A or B" - exactly one selected
- "Deploy to staging or production" - exactly one environment

## Relationships

### DEPENDS_ON
```cypher
(Node)-[:DEPENDS_ON {
  id: string,              // Unique identifier (UUID, REQUIRED)
  created_at: int | null   // When dependency was added (optional, for future temporal logic)
}]->(Node)
```

**Semantics:**
- `(A)-[:DEPENDS_ON]->(B)` means "A depends on B"
- Works for all node types (Task, And, Or, Not, ExactlyOne)
- Same relationship as before - NO CHANGE!

## Computed Properties

### Node Value (Completion Status)

Each node computes its boolean value using the formula: **`calculated_value = own_value AND deps_clear`**

Where `deps_clear` is the gate-specific evaluation of dependencies:

| Node Type | own_value | deps_clear (gate logic) | calculated_value |
|-----------|-----------|------------------------|------------------|
| **Task**  | `completed` | `all(inputs)` (AND) | `completed AND all(inputs)` |
| **And**   | `true` | `all(inputs)` | `all(inputs)` |
| **Or**    | `true` | `any(inputs)` | `any(inputs)` |
| **Not**   | `true` | `!(any(inputs))` (NOR) | `!(any(inputs))` |
| **ExactlyOne** | `true` | `count(inputs) == 1` | `count(inputs) == 1` |

**Empty inputs:**
- Task/And: `true` (vacuous truth - empty conjunction)
- Or/ExactlyOne: `false` (no option satisfied)
- Not: `true` (nothing to negate)

### Calculated Due Date

For ALL nodes (including gates):

```
calculated_due = min(
  node.due,                              // Own due date (if set)
  min(downstream_nodes.calculated_due)   // Earliest downstream due
)
```

## Constraints

### Uniqueness
```cypher
// All node IDs must be unique across all types
CREATE CONSTRAINT node_id_unique IF NOT EXISTS
FOR (n:Node) REQUIRE n.id IS UNIQUE;

// All DEPENDS_ON relationship IDs must be unique
CREATE CONSTRAINT depends_on_id_unique IF NOT EXISTS
FOR ()-[r:DEPENDS_ON]->() REQUIRE r.id IS UNIQUE;
```

### Structural Rules

1. **Graph must be acyclic (DAG):**
   ```cypher
   MATCH (n)-[:DEPENDS_ON*1..]->(n)
   RETURN n  // Should be empty (no cycles)
   ```

**Note:** All node types (Task, And, Or, Not, ExactlyOne) can have 0-∞ dependencies.

**Note:** All gate types (And, Or, Not, OnlyOne) accept 0-∞ inputs with well-defined semantics for all cases.

## Migration from Old Schema

### Old Schema
```cypher
(:Task {
  id: string,
  text: string,
  completed: boolean,
  inferred: boolean,        // Implicit AND gate
  due: int | null,
  created_at: int,
  updated_at: int
})

(Task)-[:DEPENDS_ON {id: string}]->(Task)
```

### Migration Steps

1. **Add :Node label to all tasks:**
   ```cypher
   MATCH (t:Task)
   SET t:Node;
   ```

2. **Convert inferred tasks to And gates:**
   ```cypher
   MATCH (t:Task)
   WHERE t.inferred = true
   SET t:And
   REMOVE t:Task, t.completed, t.inferred;
   ```

3. **Remove inferred property from regular tasks:**
   ```cypher
   MATCH (t:Task)
   WHERE t.inferred = false
   REMOVE t.inferred;
   ```

4. **No relationship changes needed - DEPENDS_ON stays as is!**

## Cypher Queries

### Get Node Value (Completion)

```cypher
// For a single node
MATCH (n:Node {id: $node_id})
OPTIONAL MATCH (n)-[:DEPENDS_ON]->(dep:Node)

WITH n,
     CASE
       WHEN n:Task THEN n.completed
       WHEN n:And THEN size([i IN collect(input) WHERE i:Task AND NOT i.completed OR i:And OR i:Or OR i:ExactlyOne OR i:Not]) = 0
       WHEN n:Or THEN size([i IN collect(input) WHERE i:Task AND i.completed]) > 0
       WHEN n:Not THEN size([i IN collect(input) WHERE i:Task AND i.completed]) = 0
       WHEN n:ExactlyOne THEN size([i IN collect(input) WHERE i:Task AND i.completed]) = 1
     END as value

RETURN n, value;
```

### Get All Actionable Tasks

Tasks that are not complete and have all dependencies satisfied:

```cypher
MATCH (t:Task)
WHERE NOT t.completed

// Check if task has any incomplete dependencies
OPTIONAL MATCH (gate)-[:DEPENDS_ON]->(t)
OPTIONAL MATCH (gate)-[:DEPENDS_ON]->(dependency)
WHERE dependency <> t

WITH t,
     collect(DISTINCT dependency) as deps,
     size([d IN collect(DISTINCT dependency) WHERE d:Task AND NOT d.completed]) as incomplete_deps

WHERE incomplete_deps = 0

RETURN t;
```

### Get Subgraph

```cypher
MATCH path = (n:Node {id: $node_id})-[:DEPENDS_ON*0..]->(leaf)
RETURN nodes(path), relationships(path);
```

## Examples

### Example 1: Simple Task
```cypher
CREATE (:Node:Task {
  id: "write-code",
  text: "Write the feature code",
  completed: false,
  due: null,
  created_at: timestamp(),
  updated_at: timestamp()
});
```

### Example 2: And Gate (All Must Complete)
```cypher
CREATE (gate:Node:And {
  id: "backend-ready",
  text: "Backend Ready to Deploy",
  due: null,
  created_at: timestamp(),
  updated_at: timestamp()
});

MATCH (gate:Node {id: "backend-ready"})
MATCH (t1:Node {id: "write-code"})
MATCH (t2:Node {id: "write-tests"})
MATCH (t3:Node {id: "write-docs"})
CREATE (gate)-[:DEPENDS_ON {id: randomUUID()}]->(t1)
CREATE (gate)-[:DEPENDS_ON {id: randomUUID()}]->(t2)
CREATE (gate)-[:DEPENDS_ON {id: randomUUID()}]->(t3);
```

### Example 3: Or Gate (Any Can Complete)
```cypher
CREATE (gate:Node:Or {
  id: "deployed",
  text: "App Deployed (any method)",
  due: null,
  created_at: timestamp(),
  updated_at: timestamp()
});

MATCH (gate:Node {id: "deployed"})
MATCH (t1:Node {id: "docker-deploy"})
MATCH (t2:Node {id: "k8s-deploy"})
CREATE (gate)-[:DEPENDS_ON {id: randomUUID()}]->(t1)
CREATE (gate)-[:DEPENDS_ON {id: randomUUID()}]->(t2);
```

### Example 4: Not Gate (NOR - All Must Be Incomplete)
```cypher
CREATE (gate:Node:Not {
  id: "no-blockers",
  text: "No Blockers Present",
  due: null,
  created_at: timestamp(),
  updated_at: timestamp()
});

MATCH (gate:Node {id: "no-blockers"})
MATCH (b1:Node {id: "blocker-1"})
MATCH (b2:Node {id: "blocker-2"})
MATCH (b3:Node {id: "blocker-3"})
CREATE (gate)-[:DEPENDS_ON {id: randomUUID()}]->(b1)
CREATE (gate)-[:DEPENDS_ON {id: randomUUID()}]->(b2)
CREATE (gate)-[:DEPENDS_ON {id: randomUUID()}]->(b3);

// no-blockers.value = true when ALL blockers are incomplete
```

### Example 5: ExactlyOne Gate
```cypher
CREATE (gate:Node:OnlyOne {
  id: "approach-chosen",
  text: "Exactly One Approach Chosen",
  due: null,
  created_at: timestamp(),
  updated_at: timestamp()
});

MATCH (gate:Node {id: "approach-chosen"})
MATCH (t1:Node {id: "approach-a"})
MATCH (t2:Node {id: "approach-b"})
CREATE (gate)-[:DEPENDS_ON {id: randomUUID()}]->(t1)
CREATE (gate)-[:DEPENDS_ON {id: randomUUID()}]->(t2);

// approach-chosen.value = true when exactly one is complete
```

## Property Reference

### Required Properties (All Nodes)
- `id`: string (unique)
- `created_at`: int (unix timestamp)
- `updated_at`: int (unix timestamp)

### Optional Properties (All Nodes)
- `text`: string (description)
- `due`: int (unix timestamp)

### Task-Only Properties
- `completed`: boolean (REQUIRED for Task nodes)

### Properties NOT Used
- `inferred`: Removed (replaced by :And label)
- `calculated_completed`: Computed on-demand, not stored

## Actionability & UI Semantics

### Computed Properties Formula

**Universal formula:** `calculated_value = own_value AND deps_clear`

Where:
- `own_value` = Task: `completed`, Gates: `true` (identity)
- `deps_clear` = gate-specific evaluation of dependencies (ignores own state)

### For Tasks:
- **calculated_value** = `completed AND deps_clear` = `completed AND all(deps.calculated_value)`
- **deps_clear** = `all(deps.calculated_value)` (uses AND gate logic)
- **is_actionable** = `deps_clear AND NOT completed` (can work on it now)
- Tasks are the only nodes that can be manually completed

### For Gates (And, Or, Not, ExactlyOne):
- **calculated_value** = `deps_clear` (no own state to AND with)
- **deps_clear** = gate-specific logic applied to `deps.calculated_value`
  - And: `all(deps)`
  - Or: `any(deps)`
  - Not: `!(any(deps))` (NOR)
  - ExactlyOne: `sum(deps) == 1`
- **is_actionable** = `false` (never actionable - computed automatically)

### Visual States:
- **Blocked Task** = `!deps_clear` (prerequisites not met - cannot start)
- **Actionable Task** = `deps_clear && !completed` (prerequisites met - ready to work on)
- **Complete** = `calculated_value == true` (logically complete)
- **Inconsistent Task** = `completed && !deps_clear` (marked done but deps not met - shows as incomplete)

## Notes

- **Type Storage:** Node type stored in LABELS only (`:Task`, `:And`, etc.) - no redundant property
- **Functionally Complete:** And, Or, Not form a complete boolean logic set
- **ExactlyOne Added:** For "exactly one" scenarios (mutually exclusive choices)
- **Not is NOR:** Multi-input Not = true when ALL inputs are incomplete
- **Tasks vs Gates:** Tasks have manual `completed`, Gates compute from inputs
- **Gate Auto-calculation:** Gates always compute value, never manually set
- **Temporal Logic:** `DEPENDS_ON.created_at` reserved for future completion invalidation feature
