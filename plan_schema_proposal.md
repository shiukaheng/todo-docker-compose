# Plan Schema Proposal

## Overview

Plans allow users to manually define ordered sequences of tasks/nodes for execution. This is separate from the algorithmic dependency graph - plans are user-curated execution sequences that can span multiple parts of the task graph.

## Node Schema

### Plan Node

```cypher
(:Plan {
  id: string,              // Unique identifier
  name: string,            // User-facing name
  description: string | null,  // Optional description
  created_at: int,         // Unix timestamp
  updated_at: int          // Unix timestamp
})
```

### PlanStep Node

```cypher
(:PlanStep {
  id: string,              // Unique identifier (UUID)
  plan_id: string,         // Foreign key to plan (redundant with relationship)
  order: int,              // Position in sequence (1, 2, 3, ...)
  notes: string | null,    // Optional step-specific notes
  completed: boolean,      // Track step completion (default: false)
  created_at: int          // Unix timestamp
})
```

**Note:** `plan_id` is stored on PlanStep (redundant with HAS_STEP relationship) to enable the composite uniqueness constraint on `(plan_id, order)`.

## Relationships

```cypher
// Plan owns its steps
(:Plan)-[:HAS_STEP]->(:PlanStep)

// Step refers to a node in the task graph (REQUIRED)
(:PlanStep)-[:REFERS_TO]->(:Node)
```

**Semantics:**
- `HAS_STEP`: One plan has many steps (1:N)
- `REFERS_TO`: One step refers to exactly one node (1:1, required)
  - Every step must point to a node in the task graph
  - A step cannot refer to multiple nodes

## Constraints

```cypher
// 1. Plan IDs must be unique
CREATE CONSTRAINT plan_id_unique IF NOT EXISTS
FOR (p:Plan) REQUIRE p.id IS UNIQUE;

// 2. PlanStep IDs must be unique
CREATE CONSTRAINT plan_step_id_unique IF NOT EXISTS
FOR (s:PlanStep) REQUIRE s.id IS UNIQUE;

// 3. Within a plan, order values must be unique (no duplicate positions)
CREATE CONSTRAINT plan_step_order_unique IF NOT EXISTS
FOR (s:PlanStep) REQUIRE (s.plan_id, s.order) IS UNIQUE;

// 4. plan_id must exist (referential integrity helper)
CREATE CONSTRAINT plan_step_plan_id_exists IF NOT EXISTS
FOR (s:PlanStep) REQUIRE s.plan_id IS NOT NULL;

// 5. order must exist and be positive
CREATE CONSTRAINT plan_step_order_exists IF NOT EXISTS
FOR (s:PlanStep) REQUIRE s.order IS NOT NULL;

// 6. Every PlanStep must refer to a Node (relationship existence)
CREATE CONSTRAINT plan_step_refers_to_exists IF NOT EXISTS
FOR (s:PlanStep) REQUIRE EXISTS((s)-[:REFERS_TO]->());
```

**Why store plan_id on PlanStep?**
- Enables constraint #3: `(plan_id, order)` uniqueness
- Allows indexed queries: `MATCH (s:PlanStep {plan_id: $id, order: $n})`
- Redundant with HAS_STEP relationship, but worth it for data integrity

## Validation Rules

1. **Order values must be positive integers**: `order >= 1`
2. **Order values should be sequential**: Recommended but not enforced (gaps allowed)
3. **HAS_STEP relationship must match plan_id**: Application must ensure consistency
4. **Completed field**: Optional, can track execution progress

## Common Operations

### Create Plan with Steps

```cypher
// Create plan
CREATE (p:Plan {
  id: $plan_id,
  name: $name,
  description: $description,
  created_at: timestamp(),
  updated_at: timestamp()
})

// Add steps
UNWIND $steps AS step
CREATE (s:PlanStep {
  id: randomUUID(),
  plan_id: $plan_id,
  order: step.order,
  notes: step.notes,
  completed: false,
  created_at: timestamp()
})
CREATE (p)-[:HAS_STEP]->(s)

// Link to task nodes
WITH s, step
MATCH (n:Node {id: step.node_id})
CREATE (s)-[:REFERS_TO]->(n)

RETURN p
```

### Get Plan with Steps in Order

```cypher
MATCH (p:Plan {id: $plan_id})-[:HAS_STEP]->(step:PlanStep)
OPTIONAL MATCH (step)-[:REFERS_TO]->(node:Node)
RETURN p, step, node
ORDER BY step.order ASC
```

### Insert Step at Position

**Option A: Fractional ordering (no renumbering)**
```cypher
// Insert between order 2 and 3 → use order 2.5
MATCH (p:Plan {id: $plan_id})
CREATE (s:PlanStep {
  id: randomUUID(),
  plan_id: $plan_id,
  order: 2.5,  // or calculate: (prev.order + next.order) / 2
  notes: $notes,
  completed: false,
  created_at: timestamp()
})
CREATE (p)-[:HAS_STEP]->(s)
```

**Option B: Shift subsequent steps (renumbering)**
```cypher
// Insert at order 3 → shift 3,4,5,... to 4,5,6,...
MATCH (p:Plan {id: $plan_id})-[:HAS_STEP]->(s:PlanStep)
WHERE s.order >= $insert_at
SET s.order = s.order + 1

WITH p
CREATE (new:PlanStep {
  id: randomUUID(),
  plan_id: $plan_id,
  order: $insert_at,
  notes: $notes,
  completed: false,
  created_at: timestamp()
})
CREATE (p)-[:HAS_STEP]->(new)
```

**Recommendation:** Use fractional ordering for simplicity, with periodic "compaction" to integers if needed.

### Reorder Step (Move Position)

```cypher
// Move step from order A to order B
MATCH (s:PlanStep {plan_id: $plan_id, order: $from})
SET s.order = $to

// If needed, shift other steps to avoid conflicts
// (depends on whether you allow fractional or need renumbering)
```

### Delete Step

```cypher
// Simple deletion (leaves gap in order)
MATCH (s:PlanStep {plan_id: $plan_id, order: $order})
DETACH DELETE s

// With renumbering (shift down subsequent steps)
MATCH (p:Plan {id: $plan_id})-[:HAS_STEP]->(del:PlanStep {order: $order})
DETACH DELETE del

WITH p
MATCH (p)-[:HAS_STEP]->(s:PlanStep)
WHERE s.order > $order
SET s.order = s.order - 1
```

### Delete Entire Plan

```cypher
// Delete plan and all its steps
MATCH (p:Plan {id: $plan_id})-[:HAS_STEP]->(s:PlanStep)
DETACH DELETE p, s
```

### Handle Orphaned Steps (Node Deleted)

When a Node is deleted, PlanSteps that refer to it become invalid and must be handled:

```cypher
// Find and delete steps that refer to deleted nodes
MATCH (step:PlanStep)
WHERE NOT EXISTS((step)-[:REFERS_TO]->(:Node))
DETACH DELETE step

// This should be run as a cleanup after deleting nodes, or use CASCADE delete:
MATCH (n:Node {id: $node_id})
OPTIONAL MATCH (step:PlanStep)-[:REFERS_TO]->(n)
DETACH DELETE n, step  // Delete node and any plan steps referencing it
```

## Data Integrity

### Consistency Checks

```cypher
// Check 1: Every PlanStep has exactly one Plan via HAS_STEP
MATCH (s:PlanStep)
WITH s, [(p:Plan)-[:HAS_STEP]->(s) | p] AS plans
WHERE size(plans) <> 1
RETURN s, plans  // Should be empty

// Check 2: PlanStep.plan_id matches HAS_STEP relationship
MATCH (p:Plan)-[:HAS_STEP]->(s:PlanStep)
WHERE s.plan_id <> p.id
RETURN p, s  // Should be empty

// Check 3: No duplicate orders in same plan (enforced by constraint)
MATCH (s1:PlanStep), (s2:PlanStep)
WHERE s1.plan_id = s2.plan_id
  AND s1.order = s2.order
  AND id(s1) < id(s2)
RETURN s1, s2  // Should be empty (constraint prevents this)
```

### Cleanup Operations

```cypher
// Remove orphaned steps (plan deleted but steps remain)
MATCH (s:PlanStep)
WHERE NOT EXISTS((:Plan)-[:HAS_STEP]->(s))
DETACH DELETE s

// Compact fractional orders back to integers
MATCH (p:Plan {id: $plan_id})-[:HAS_STEP]->(s:PlanStep)
WITH s ORDER BY s.order
WITH collect(s) AS steps
UNWIND range(0, size(steps)-1) AS idx
SET (steps[idx]).order = idx + 1
```

## Edge Cases

1. **Empty Plan**: Plan with no steps (valid)
2. **Gaps in order**: Orders 1, 2, 5, 7 (valid but not ideal)
3. **Fractional orders**: Orders 1, 1.5, 2, 2.25 (valid with float order type)
4. **Negative orders**: Should be prevented by application logic
5. **Duplicate orders**: Prevented by constraint
6. **Node deleted**: PlanSteps referencing it become invalid and should be deleted

## Example

```cypher
// Create "Morning Routine" plan
CREATE (p:Plan {
  id: "morning-routine",
  name: "Morning Routine",
  description: "Daily startup tasks",
  created_at: timestamp(),
  updated_at: timestamp()
})

// Link to existing tasks
MATCH (task1:Node {id: "review-calendar"})
MATCH (task2:Node {id: "standup-meeting"})
MATCH (task3:Node {id: "check-email"})

// Create steps
CREATE (s1:PlanStep {
  id: randomUUID(),
  plan_id: "morning-routine",
  order: 1,
  notes: "Do this first thing",
  completed: false,
  created_at: timestamp()
})
CREATE (s2:PlanStep {
  id: randomUUID(),
  plan_id: "morning-routine",
  order: 2,
  notes: NULL,
  completed: false,
  created_at: timestamp()
})
CREATE (s3:PlanStep {
  id: randomUUID(),
  plan_id: "morning-routine",
  order: 3,
  notes: "Before starting work",
  completed: false,
  created_at: timestamp()
})

CREATE (p)-[:HAS_STEP]->(s1)-[:REFERS_TO]->(task1)
CREATE (p)-[:HAS_STEP]->(s2)-[:REFERS_TO]->(task2)
CREATE (p)-[:HAS_STEP]->(s3)-[:REFERS_TO]->(task3)
```

Result:
- Step 1: Points to "review-calendar" task with note "Do this first thing"
- Step 2: Points to "standup-meeting" task
- Step 3: Points to "check-email" task with note "Before starting work"

## Migration

No migration needed - this is a new feature. Initialize with:

```cypher
// Create constraints
CREATE CONSTRAINT plan_id_unique IF NOT EXISTS
FOR (p:Plan) REQUIRE p.id IS UNIQUE;

CREATE CONSTRAINT plan_step_id_unique IF NOT EXISTS
FOR (s:PlanStep) REQUIRE s.id IS UNIQUE;

CREATE CONSTRAINT plan_step_order_unique IF NOT EXISTS
FOR (s:PlanStep) REQUIRE (s.plan_id, s.order) IS UNIQUE;

CREATE CONSTRAINT plan_step_plan_id_exists IF NOT EXISTS
FOR (s:PlanStep) REQUIRE s.plan_id IS NOT NULL;

CREATE CONSTRAINT plan_step_order_exists IF NOT EXISTS
FOR (s:PlanStep) REQUIRE s.order IS NOT NULL;

CREATE CONSTRAINT plan_step_refers_to_exists IF NOT EXISTS
FOR (s:PlanStep) REQUIRE EXISTS((s)-[:REFERS_TO]->());
```

## Open Questions

1. **Should order be integer or float?**
   - Integer: Clean, but requires renumbering on insert
   - Float: Fractional ordering, but can accumulate precision issues
   - Recommendation: Use integer with occasional compaction

2. **Should completed be on PlanStep?**
   - Useful for tracking execution progress
   - But task completion is tracked on Node - potential confusion
   - Recommendation: Keep it - represents "I did this step" vs "task is complete"

3. **Should steps be reusable across plans?**
   - Current design: No (each step belongs to one plan)
   - Alternative: Steps are shared, linked via different relationships
   - Recommendation: Keep it simple - one step per plan

4. **What about pure notes/instructions?**
   - Since PlanSteps must reference a Node, users can create special note nodes if needed
   - Alternative: Use the `notes` field on PlanStep for additional context
   - Recommendation: Notes field provides enough flexibility for annotations

5. **Maximum plan size?**
   - No hard limit, but UX should warn if > 50 steps
   - Large plans might indicate need for sub-plans or better task decomposition
