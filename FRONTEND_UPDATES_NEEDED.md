# Frontend Updates Needed for Boolean Graph

## Current Frontend Logic (styleGraphData.ts)

```typescript
const isBlocked = childTaskIds.length > 0 && childTaskIds.some(id => !taskCalcCompleted.get(id));
const isCompleted = !isBlocked && data.calculatedCompleted;
const isActionable = !isBlocked && !isCompleted;
```

## Issues with New Node Types

1. **Gates are never actionable** (can't be manually worked on)
2. **Need to differentiate Tasks from Gates in UI**
3. **Shape logic needs updating** (currently only checks `inferred`)

## Required Changes

### 1. Update isActionable Logic

```typescript
// OLD (manually computed)
const isBlocked = childTaskIds.length > 0 && childTaskIds.some(id => !taskCalcCompleted.get(id));
const isCompleted = !isBlocked && data.calculatedCompleted;
const isActionable = !isBlocked && !isCompleted;

// NEW (use backend value)
const isActionable = data.is_actionable;
// Or if you want to compute it yourself:
// const isActionable = data.node_type === "Task" && !data.completed && data.deps_clear;
```

**Reasoning:**
- Only Tasks are actionable (can be manually completed)
- Gates (And, Or, Not, ExactlyOne) auto-compute, never actionable
- Backend now calculates is_actionable for consistency

### 2. Update Shape Logic

```typescript
// OLD
const shape: NodeShape = isInferred ? 'upTriangle' : 'square';

// NEW
const shape: NodeShape = {
  'Task': 'square',
  'And': 'upTriangle',
  'Or': 'diamond',
  'Not': 'downTriangle',
  'ExactlyOne': 'hexagon'
}[nodeType] || 'square';
```

### 3. Update Completion/Blocked Logic

```typescript
// OLD
const isBlocked = childTaskIds.length > 0 && childTaskIds.some(id => !taskCalcCompleted.get(id));
const isCompleted = !isBlocked && data.calculatedCompleted;

// NEW
const isBlocked = !data.deps_clear;  // Backend calculates this
const isCompleted = data.calculated_value === true;  // Renamed field
```

**Note:** `deps_clear` tells you if all dependencies are satisfied. For display:
- `!deps_clear` = blocked (dependencies incomplete)
- `calculated_value === true` = completed (node's value is true)

### 4. API Response Changes

Backend now returns:
```typescript
{
  node_type: "Task" | "And" | "Or" | "Not" | "ExactlyOne",  // NEW
  calculated_value: boolean | null,  // Renamed from calculated_completed
  is_actionable: boolean | null,      // NEW: true only for unblocked incomplete Tasks
  deps_clear: boolean | null,         // NEW: all dependencies satisfied
  // inferred: removed
}
```

## UI Color/Style Suggestions

### Node Shapes
- **Task**: Square (manual work)
- **And**: Up Triangle (all inputs required)
- **Or**: Diamond (any input works)
- **Not**: Down Triangle (inversion)
- **ExactlyOne**: Hexagon (mutual exclusion)

### Node States
- **Actionable Task**: Hollow square, bright color
- **Blocked Task**: Hollow square, dim color
- **Complete Task**: Filled square
- **Gate (incomplete)**: Hollow shape, auto-computed
- **Gate (complete)**: Filled shape, auto-computed

### Visual Hierarchy
- Tasks: Primary focus (user can act on them)
- Gates: Secondary (show structure, auto-computed)

## Migration Steps

1. Update API client types (`node_type`, `calculated_value`)
2. Update `styleGraphData.ts` with new logic
3. Update shape rendering for new gate types
4. Test with mixed graph (Tasks + Gates)
5. Remove `inferred` references

## Backward Compatibility

During migration, support both:
```typescript
const nodeType = data.node_type || (data.inferred ? "And" : "Task");
const value = data.calculated_value ?? data.calculatedCompleted;
```

Once backend fully migrated, remove old field references.
