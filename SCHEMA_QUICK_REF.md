# Boolean Graph Schema - Quick Reference

## Node Types (Label-Only)

**Type stored in LABELS only** - no `node_type` property!

| Label | Properties | 0 inputs | 1 input | N inputs |
|-------|-----------|----------|---------|----------|
| `:Task` | `completed: bool` | `completed` | - | - |
| `:And` | - | `true` | pass-through | `all(inputs)` |
| `:Or` | - | `false` | pass-through | `any(inputs)` |
| `:Not` | - | `true` | `!input` | NOR |
| `:ExactlyOne` | - | `false` | pass-through | exactly one |

**All nodes:** `:Node` + type label, `id`, `text?`, `due?`, `created_at`, `updated_at`

## Relationships

```cypher
(Node)-[:DEPENDS_ON {id: string, created_at: int?}]->(Node)
```

**Same as before - NO CHANGE!**

## Migration Commands

```cypher
# 1. Add :Node label
MATCH (t:Task) SET t:Node;

# 2. Convert inferred → And
MATCH (t:Task {inferred: true})
SET t:And
REMOVE t:Task, t.completed, t.inferred;

# 3. Clean regular tasks
MATCH (t:Task {inferred: false})
REMOVE t.inferred;

# 4. No relationship changes - DEPENDS_ON stays!

# 5. Update constraints
DROP CONSTRAINT task_id_unique IF EXISTS;
CREATE CONSTRAINT node_id_unique IF NOT EXISTS
FOR (n:Node) REQUIRE n.id IS UNIQUE;
```

## Type Changes

```cypher
# Task → And (remove completed, change label)
MATCH (n:Task {id: $id})
REMOVE n:Task SET n:And REMOVE n.completed;

# And → Task (add completed, change label)
MATCH (n:And {id: $id})
REMOVE n:And SET n:Task, n.completed = false;

# Read type from labels in backend
RETURN labels(n)  // ["Node", "Task"]
```

## Key Queries

### Node value
```cypher
// Task:    n.completed
// And:     all inputs complete
// Or:      any input complete
// Not:     NO inputs complete (NOR)
// ExactlyOne: exactly one input complete
```

### Actionable tasks
```cypher
MATCH (t:Task) WHERE NOT t.completed
// ... and all dependencies satisfied
```

## Constraints

```cypher
// Unique IDs
FOR (n:Node) REQUIRE n.id IS UNIQUE;

// DAG (no cycles)
// All gates: 0-∞ inputs (flexible!)
// Tasks: 0 inputs only (leaf nodes)
```
