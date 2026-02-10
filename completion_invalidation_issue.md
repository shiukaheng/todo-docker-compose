# Completion Invalidation Issue & Proposed Solution

## Problem Statement

When dependencies are added to an already-completed task, the completion becomes stale but the system doesn't recognize this, leading to "magical" completion when dependencies are later satisfied.

### Concrete Example

```
Timeline:
T1: User creates Task A, marks it complete (A.completed = true)
T2: User adds dependency: A depends on B (realizes A needs B first)
T3: B is incomplete (B.completed = false)
    → A.calculated_completed = false ✓ (correctly blocked)
T4: User completes B (B.completed = true)
    → A.calculated_completed = true ⚠️ (magically complete without user action!)
```

**The Issue:** Task A appears completed at T4 even though:
1. It was marked complete at T1 (before dependency existed)
2. User never re-confirmed completion after B was added
3. The completion at T1 is causally invalid (happened before dependency was created)

## Current System Behavior

**Current Logic:**
```cypher
calculated_completed = (task.inferred OR task.completed) AND all(deps.completed)
```

**Schema:**
```cypher
(:Task {
  id: string,
  completed: boolean,  // Manual completion flag (no timestamp)
  inferred: boolean,
  ...
})

(Task)-[:DEPENDS_ON {id: string}]->(Task)  // No created_at tracking
```

**Problem:** The `completed` flag is timeless - it doesn't know when it was set relative to when dependencies were added.

## Root Cause

**Missing temporal information:**
- No `completed_at` timestamp on tasks
- No `created_at` timestamp on dependencies
- Cannot determine causal relationship between completion and dependency creation

**Consequence:** Stale completions remain valid even when dependency structure changes.

## Proposed Solution: Temporal Causality

### Schema Changes

Add timestamps to track causality:

```cypher
(:Task {
  id: string,
  completed: boolean,
  completed_at: int | null,  // NEW: When task was marked complete
  inferred: boolean,
  created_at: int,
  updated_at: int,
  ...
})

(Task)-[:DEPENDS_ON {
  id: string,
  created_at: int  // NEW: When dependency was created
}]->(Task)
```

### Updated Logic

```cypher
calculated_completed = (
  (task.inferred OR task.completed)
  AND all(dependencies.completed)
  AND (
    // Inferred tasks auto-complete, no timestamp check needed
    task.inferred
    OR
    // Regular tasks: ensure no dependencies added after completion
    NOT EXISTS(dep WHERE dep.created_at > task.completed_at)
  )
)
```

**Interpretation:** A task is calculated complete if:
1. It's marked complete (or inferred)
2. All dependencies are complete
3. For regular tasks: completion happened AFTER all dependencies were created

### How It Solves the Issue

**Same example with timestamps:**

```
T1 (1000): User creates Task A, marks complete
           A.completed = true, A.completed_at = 1000

T2 (2000): User adds dependency A → B
           dep.created_at = 2000

T3 (3000): B is incomplete
           A.calculated_completed = false
           Reason: dep.created_at (2000) > A.completed_at (1000)

T4 (4000): User completes B
           B.completed = true, B.completed_at = 4000
           A.calculated_completed = false (still!)
           Reason: A.completed_at (1000) is still stale

T5 (5000): User RE-COMPLETES A (after seeing it's blocked)
           A.completed = true, A.completed_at = 5000
           A.calculated_completed = true ✓
           Reason: A.completed_at (5000) > dep.created_at (2000)
```

**Key improvement:** Task A doesn't magically become complete at T4. User must explicitly re-complete it at T5.

## Implementation Details

### Setting Completion

**Mark as complete:**
```cypher
MATCH (t:Task {id: $task_id})
SET t.completed = true,
    t.completed_at = timestamp(),
    t.updated_at = timestamp()
```

**Mark as incomplete:**
```cypher
MATCH (t:Task {id: $task_id})
SET t.completed = false,
    t.completed_at = null,  // Clear timestamp
    t.updated_at = timestamp()
```

### Creating Dependencies

```cypher
MATCH (from:Task {id: $from_id}), (to:Task {id: $to_id})
CREATE (from)-[dep:DEPENDS_ON {
  id: randomUUID(),
  created_at: timestamp()  // Record when dependency was added
}]->(to)
```

### Query for Calculated Completion

```cypher
MATCH (t:Task)
OPTIONAL MATCH (t)-[dep_rel:DEPENDS_ON]->(dep:Task)

WITH t,
     collect(dep) AS all_deps,
     collect(dep_rel) AS all_dep_rels

// Check if all dependencies are complete
WITH t, all_deps, all_dep_rels,
     size([d IN all_deps WHERE NOT d.completed]) = 0 AS deps_satisfied

// Check if any dependency was added after completion
WITH t, all_deps, all_dep_rels, deps_satisfied,
     size([r IN all_dep_rels WHERE r.created_at > t.completed_at]) > 0 AS has_stale_deps

RETURN t,
  (t.inferred OR t.completed)
  AND deps_satisfied
  AND (
    t.inferred
    OR t.completed_at IS NULL  // Not completed yet
    OR NOT has_stale_deps       // No deps added after completion
  ) AS calculated_completed
```

## Edge Cases & Behavior

### Case 1: Retroactive Dependency (Both Tasks Complete)

```
T1 (1000): Complete A (A.completed_at = 1000)
T2 (2000): Complete B (B.completed_at = 2000)
T3 (3000): Add dependency A → B (dep.created_at = 3000)
```

**Result:**
- A.calculated_completed = false (1000 < 3000)
- Even though B is complete, A's completion is stale
- User must re-complete A to confirm it's still valid

**Rationale:** User added dependency retroactively, should re-verify completion.

### Case 2: Task Refinement (Breaking Down Completed Task)

```
T1 (1000): Complete A (A.completed_at = 1000)
T2 (2000): Add dependencies: A → B, A → C (both incomplete)
```

**Result:**
- A.calculated_completed = false (completion is stale)
- Must complete B, C, then re-complete A

**Rationale:** Task was refined into subtasks, needs fresh completion.

### Case 3: Dependency Removed Then Re-added

```
T1 (1000): Add dependency A → B (dep1.created_at = 1000)
T2 (2000): Complete A (A.completed_at = 2000)
T3 (3000): Remove dependency A → B
           A.calculated_completed = true (no deps, completion valid)
T4 (4000): Re-add dependency A → B (dep2.created_at = 4000)
```

**Result:**
- A.calculated_completed = false (2000 < 4000)
- New dependency instance has new timestamp
- Must re-complete A

**Rationale:** Each dependency creation is a new event requiring revalidation.

### Case 4: Inferred Tasks (Auto-completion)

```
T1 (1000): Create inferred task I with dependencies
T2 (2000): Add new dependency I → X
T3 (3000): Complete all dependencies including X
```

**Result:**
- I.calculated_completed = true (inferred tasks skip timestamp check)

**Rationale:** Inferred tasks auto-complete based on dependencies, no manual completion to invalidate.

### Case 5: No Dependencies

```
T1 (1000): Complete A (no dependencies)
T2 (2000): Check calculated_completed
```

**Result:**
- A.calculated_completed = true
- No dependencies to check against
- Completion is always valid

## UX Implications

### Visual Indicators

**Task states:**
1. **Complete & valid** (green): `completed = true`, `calculated_completed = true`
2. **Complete but stale** (yellow): `completed = true`, `calculated_completed = false`, has deps added after `completed_at`
3. **Blocked by dependencies** (yellow): `completed = true`, `calculated_completed = false`, has incomplete deps
4. **Incomplete** (default): `completed = false`

### User Messages

**When adding dependency to completed task:**
```
"Dependency added. This task needs re-completion after 'Task B' is done."
```

**When viewing stale task:**
```
"Task was completed on Jan 1, but dependencies were added on Jan 5.
Please re-complete this task to confirm it's still done."
```

**When completing dependency:**
```
"Task B complete. Task A still needs re-completion (dependencies changed)."
```

## Migration Strategy

### Adding Timestamps to Existing Data

```cypher
// 1. Add completed_at to existing completed tasks (use updated_at as approximation)
MATCH (t:Task)
WHERE t.completed = true AND t.completed_at IS NULL
SET t.completed_at = t.updated_at

// 2. Add created_at to existing dependencies (use current time)
MATCH ()-[r:DEPENDS_ON]->()
WHERE r.created_at IS NULL
SET r.created_at = timestamp()

// 3. For conservative migration: Set all existing completed tasks to need revalidation
//    by backdating their completed_at (optional)
MATCH (t:Task)
WHERE t.completed = true
SET t.completed_at = 0  // Forces revalidation against all dependencies
```

**Trade-off:**
- Option A (use updated_at): Less disruption, but might allow stale completions
- Option B (backdate to 0): Forces all completed tasks to revalidate, more accurate but disruptive

**Recommendation:** Option A for existing data, strict enforcement for new data going forward.

## Alternative Solutions Considered

### Alternative 1: Reset completed flag on dependency add

**Approach:**
```cypher
MATCH (a:Task {id: $a_id}), (b:Task {id: $b_id})
WHERE a.completed = true
CREATE (a)-[:DEPENDS_ON]->(b)
SET a.completed = false  // Auto-reset
```

**Pros:** Simple, forces explicit re-completion
**Cons:** Surprising UX, loses completion history
**Verdict:** ❌ Too aggressive, poor UX

### Alternative 2: Invalidation flag

**Approach:**
```cypher
(:Task {
  completed: boolean,
  needs_revalidation: boolean  // Set when deps added to completed task
})
```

**Pros:** Explicit invalidation
**Cons:** Binary flag, no temporal precision, extra state management
**Verdict:** ❌ Less elegant than timestamps

### Alternative 3: Dependency version counter

**Approach:**
```cypher
(:Task {
  completed_at_version: int,  // Dep version when completed
  current_dep_version: int     // Increments on dep changes
})
```

**Pros:** Clean versioning concept
**Cons:** Less precise than timestamps, harder to debug
**Verdict:** ❌ Timestamps provide more information

### Alternative 4: Do nothing (current behavior)

**Approach:** Accept that completions can become magically valid

**Pros:** No implementation cost
**Cons:** Incorrect semantics, user confusion, data integrity issues
**Verdict:** ❌ Unacceptable for production use

## Conclusion

**Recommended Solution:** Add `completed_at` timestamps to tasks and `created_at` timestamps to dependencies.

**Key Benefits:**
1. ✅ Correct causality (completion must happen after dependencies exist)
2. ✅ Preserves history (know when tasks were completed)
3. ✅ Clear UX (show users when revalidation needed)
4. ✅ Enables analytics (completion patterns, task duration)
5. ✅ Handles all edge cases consistently

**Implementation Priority:** High - affects data integrity and user trust

**Next Steps:**
1. Update schema proposal documents
2. Implement timestamp tracking in backend
3. Update calculated_completed query logic
4. Add UI indicators for stale completions
5. Migrate existing data with chosen strategy
