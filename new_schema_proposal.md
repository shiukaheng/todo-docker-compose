# Boolean Logic Graph Schema Proposal

## Motivation

The current system uses "inferred" nodes to represent task groups that complete when all dependencies are met (essentially AND gates). This proposal generalizes the system into a **universal boolean function graph** by introducing explicit logic gate nodes (And, Or, Not, Xor), enabling far more expressive task dependency modeling.

## Current System

```cypher
(:Task {
  id: string,
  text: string,
  completed: boolean,
  inferred: boolean,        // Acts as implicit AND gate
  due: int | null,
  created_at: int,
  updated_at: int
})

(Task)-[:DEPENDS_ON {id: string}]->(Task)
```

**Semantics**: `(A)-[:DEPENDS_ON]->(B)` means "A depends on B" (B must complete before A)
- Inferred task completes when ALL dependencies complete (AND logic)
- Regular task completes when manually marked

## Proposed System

### Node Labels

All nodes share `:Node` label for easy querying, with specific type labels:

```cypher
(:Node:Task {
  id: string (unique),
  text: string,
  completed: boolean,        // Manual completion (Task-specific)
  due: int | null,
  created_at: int,
  updated_at: int
})

(:Node:And {
  id: string (unique),
  text: string,              // e.g., "Backend Ready"
  due: int | null,           // Deadline for this gate
  created_at: int,
  updated_at: int
  // No 'completed' - computed from inputs
})

(:Node:Or {
  id: string (unique),
  text: string,              // e.g., "Any deployment path"
  due: int | null,
  created_at: int,
  updated_at: int
})

(:Node:Not {
  id: string (unique),
  text: string,              // e.g., "Bug not present"
  due: int | null,
  created_at: int,
  updated_at: int
})

(:Node:Xor {
  id: string (unique),
  text: string,              // e.g., "Exactly one approach chosen"
  due: int | null,
  created_at: int,
  updated_at: int
})
```

### Relationships

Replace `DEPENDS_ON` with `INPUT`:

```cypher
(Gate:And|Or|Not|Xor)-[:INPUT {
  id: string (UUID),
  order: int | null          // For gates where input order matters
}]->(InputNode:Node)
```

**Semantics**: `(Gate)-[:INPUT]->(Node)` means "Gate takes Node as input"

### Computed Value (Completion Status)

Each node computes its "value" (completion status):

- **Task**: `value = completed` (manual property)
- **And**: `value = all(inputs.value == true)` - true if ALL inputs are true
- **Or**: `value = any(inputs.value == true)` - true if ANY input is true
- **Not**: `value = !input.value` - true if its single input is false
- **Xor**: `value = count(inputs.value == true) % 2 == 1` - true if ODD number of inputs are true

### Calculated Due Date

For ALL nodes (including logic gates):

```
calculated_due = min(
  node.due,                              // Own due date (if set)
  min(downstream_nodes.calculated_due)   // Earliest downstream due
)
```

Examples:
- "All tests must pass" (And node, no due) - inherits from downstream
- "Deploy by Friday" (Or node, due=Friday) - enforces deadline
- "API endpoint" (Task, due=Wednesday) - specific task deadline

## Validation Rules

1. **Task nodes**:
   - Leaf nodes only (should not have INPUT relationships)
   - Must have `completed` property

2. **Not gate**:
   - Must have EXACTLY 1 input
   - Single input validation

3. **And/Or/Xor gates**:
   - Must have AT LEAST 1 input (could require ≥2 for semantic clarity)

4. **No cycles**:
   - Same as current system: `(n)-[:INPUT*1..]->(n)` not allowed

5. **Unique IDs**:
   - Across all node types (same constraint as current system)

## Logic Gate Set Justification

### Minimal Complete Set (Recommended)
**Task, And, Or, Not**
- Functionally complete (can express any boolean function)
- Simple, intuitive mental model
- Covers 95% of task management use cases

### Why include Xor?
**Use cases for XOR:**
- "Complete project via approach A XOR approach B" (exactly one path)
- "Learn skill via course A XOR course B" (mutually exclusive options)
- "Fix bug using solution A XOR solution B" (choose one fix)

While less common than And/Or, XOR handles "choose exactly one" scenarios that can't be elegantly expressed otherwise.

### Why NOT include Nand/Nor?
- Can be expressed as `Not(And(...))` or `Not(Or(...))`
- Less intuitive for task management
- Adds complexity without significant value
- Can be added later if needed

## Migration Path

### From Current Schema

1. **Inferred Tasks → And Nodes**
   ```cypher
   MATCH (t:Task {inferred: true})
   SET t:And
   REMOVE t.completed, t.inferred
   ```

2. **Regular Tasks → Task Nodes**
   ```cypher
   MATCH (t:Task {inferred: false})
   REMOVE t.inferred
   // Keep :Task label, keep completed property
   ```

3. **DEPENDS_ON → INPUT**
   ```cypher
   MATCH (a)-[r:DEPENDS_ON]->(b)
   CREATE (a)-[:INPUT {id: r.id}]->(b)
   DELETE r
   ```

4. **Add :Node Label to All**
   ```cypher
   MATCH (n:Task)
   SET n:Node
   ```
   ```cypher
   MATCH (n:And)
   SET n:Node
   ```

## Open Questions

1. **Should logic gates allow manual override?**
   - Currently: value is strictly computed from inputs
   - Alternative: Add optional `override: boolean` property?
   - Leaning towards: No override, keep logic pure

2. **Should Task nodes be allowed to have inputs?**
   - Currently: Task = leaf node only
   - Alternative: Task can have inputs AND manual completion (hybrid)
   - Use case: "Deploy" task depends on tests, but also needs manual trigger
   - Leaning towards: Allow inputs, value = `completed AND all(inputs.value)`

3. **Input ordering for XOR?**
   - Currently: Using odd-count definition (symmetric)
   - Alternative: Sequential XOR with ordered inputs
   - Leaning towards: Odd-count (simpler, more general)

4. **Minimum input count for And/Or/Xor?**
   - Option 1: At least 1 input (edge case: single input is pass-through)
   - Option 2: At least 2 inputs (enforces semantic meaning)
   - Leaning towards: At least 1 (more flexible)

## Examples

### Example 1: Project Completion
```
(:Task {id: "write-code", completed: true})
(:Task {id: "write-tests", completed: true})
(:Task {id: "write-docs", completed: false})

(:And {id: "ready-to-deploy", text: "Ready to Deploy"})
  -[:INPUT]->(:Task {id: "write-code"})
  -[:INPUT]->(:Task {id: "write-tests"})
  -[:INPUT]->(:Task {id: "write-docs"})

// ready-to-deploy.value = false (docs not complete)
```

### Example 2: Multiple Deployment Paths
```
(:Task {id: "docker-deploy", completed: false})
(:Task {id: "k8s-deploy", completed: true})

(:Or {id: "deployed", text: "App Deployed"})
  -[:INPUT]->(:Task {id: "docker-deploy"})
  -[:INPUT]->(:Task {id: "k8s-deploy"})

// deployed.value = true (k8s path complete)
```

### Example 3: Bug Not Present
```
(:Task {id: "bug-123", completed: true})

(:Not {id: "no-bug-123", text: "Bug #123 Fixed"})
  -[:INPUT]->(:Task {id: "bug-123"})

// no-bug-123.value = false (bug task is complete, so bug still exists)
// Wait, this is backwards! Need to rethink Not semantics
```

### Example 4: Choose One Approach
```
(:Task {id: "approach-a", completed: true})
(:Task {id: "approach-b", completed: false})

(:Xor {id: "approach-chosen", text: "Exactly One Approach"})
  -[:INPUT]->(:Task {id: "approach-a"})
  -[:INPUT]->(:Task {id: "approach-b"})

// approach-chosen.value = true (exactly one is complete)
```

## Issues to Resolve

### Not Gate Semantics
The "Bug Not Present" example reveals a conceptual issue:
- If Task represents "bug exists" and is marked complete, Not(bug) = false (bug fixed)
- But we want "bug fixed" to be true when the bug is resolved

**Options:**
1. Not gate inverts as designed; users must model carefully
2. Add "Resolved" or "Inactive" state to tasks
3. Rethink what Task.completed means in negative contexts

**Recommendation:** Keep Not gate as pure boolean inversion. Users should model:
- `(:Task {id: "fix-bug-123"})` - task to fix bug
- `(:Not {id: "bug-exists"})-[:INPUT]->(:Task {id: "fix-bug-123"})` - bug exists = NOT(fix complete)

Or simply:
- `(:Task {id: "bug-fixed"})` - positive framing
