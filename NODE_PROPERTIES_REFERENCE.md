# Node Properties Reference

## Overview

This document defines all node properties used for graph visualization, their semantic meanings, calculation rules, and how the frontend should use them.

## Core Properties (Stored in Database)

### Node Identity & Type

| Property | Type | Storage | Description |
|----------|------|---------|-------------|
| `id` | string | DB | Unique identifier |
| `node_type` | string | Labels (derived) | "Task", "And", "Or", "Not", "ExactlyOne" |
| `text` | string | DB | Human-readable description |
| `created_at` | int | DB | Creation timestamp |
| `updated_at` | int | DB | Last update timestamp |

### Node State

| Property | Type | Storage | Applies To | Description |
|----------|------|---------|------------|-------------|
| `completed` | boolean | DB | **Task only** | Manual completion flag |
| `due` | int | DB | All nodes | Due date (unix timestamp) |

## Calculated Properties (Backend Computed)

### 1. calculated_value

**Semantic Meaning:** "Is this node's logical value TRUE considering both own state and dependencies?"

**Formula:** `calculated_value = own_value AND deps_clear`

**Calculation:**

```python
def calculate_value(node: Node, dependencies: list[Node]) -> bool:
    # First, calculate deps_clear (gate-specific evaluation of dependencies)
    dep_values = [calculate_value(dep) for dep in dependencies]
    deps_clear = calculate_gate_logic(node.node_type, dep_values)

    if node.node_type == "Task":
        # Task: combine own completed state with dependency satisfaction
        return node.completed and deps_clear
    else:
        # Gates: no own value, so calculated_value = deps_clear
        return deps_clear

def calculate_gate_logic(node_type: str, dep_values: list[bool]) -> bool:
    """Apply gate-specific logic to dependencies."""
    if node_type in ["Task", "And"]:
        return len(dep_values) == 0 or all(dep_values)  # AND logic
    elif node_type == "Or":
        return len(dep_values) > 0 and any(dep_values)  # OR logic
    elif node_type == "Not":
        return not any(dep_values)  # NOR logic
    elif node_type == "ExactlyOne":
        return sum(dep_values) == 1  # XOR logic
```

**Truth Table:**

| Node Type | Own Value | deps_clear (gate logic) | calculated_value |
|-----------|-----------|------------------------|------------------|
| Task | `completed` | `all(deps)` | `completed AND all(deps)` |
| And | `true` (identity) | `all(deps)` | `all(deps)` |
| Or | `true` (identity) | `any(deps)` | `any(deps)` |
| Not | `true` (identity) | `!(any(deps))` (NOR) | `!(any(deps))` |
| ExactlyOne | `true` (identity) | `sum(deps) == 1` | `sum(deps) == 1` |

**Empty inputs:**
- Task/And: `true` (vacuous truth)
- Or/ExactlyOne: `false` (no option satisfied)
- Not: `true` (nothing to negate)

**Frontend Usage:**
- Determines filled vs hollow nodes
- Shows completion status
- Drives urgency-based coloring

**Important Note on Tasks:**
- A Task can have `completed = true` but `calculated_value = false` if dependencies aren't satisfied
- This enforces logical consistency: "You marked it done, but prerequisites weren't met"
- UI should respect `calculated_value` for visual state, not just `completed`

---

### 2. deps_clear

**Semantic Meaning:** "Evaluate my gate-specific logic on dependencies (ignoring my own state)."

**This is the INNER inferred value from dependencies, specific to each node's logic gate type.**

**Calculation:**

```python
def calculate_deps_clear(node: Node, dependencies: list[Node]) -> bool:
    """Apply gate-specific logic to dependencies' calculated_value."""
    dep_values = [dep.calculated_value for dep in dependencies]

    if node.node_type in ["Task", "And"]:
        return len(dep_values) == 0 or all(dep_values)  # AND logic
    elif node.node_type == "Or":
        return len(dep_values) > 0 and any(dep_values)  # OR logic
    elif node.node_type == "Not":
        return not any(dep_values)  # NOR logic
    elif node.node_type == "ExactlyOne":
        return sum(dep_values) == 1  # XOR logic
```

**Per Node Type:**
- **Task/And:** `all(deps)` - all dependencies must be true
- **Or:** `any(deps)` - at least one dependency must be true
- **Not:** `!(any(deps))` - no dependencies must be true (NOR)
- **ExactlyOne:** `sum(deps) == 1` - exactly one dependency must be true

**Key Insight:** Independent of node's own state (for Task, ignores `completed` flag)

**Frontend Usage:**
- For Tasks: "Can I start working on this?" (are prerequisites met?)
- For Gates: Same as calculated_value (gates have no own state)
- Determines "blocked" visual state

---

### 3. is_actionable

**Semantic Meaning:** "Can the user manually interact with this node?"

**Formula:** `is_actionable = deps_clear AND NOT own_value` (only for Tasks)

**Calculation:**

```python
def calculate_is_actionable(node: Node) -> bool:
    """Only Tasks can be actionable when incomplete and unblocked."""
    if node.node_type != "Task":
        return False  # Gates are NEVER actionable

    # deps_clear (prerequisites met) AND NOT completed (work remaining)
    return node.deps_clear and not node.completed
```

**Truth Table:**

| Node Type | completed | deps_clear | is_actionable |
|-----------|-----------|------------|---------------|
| Task | false | true | **true** ✓ |
| Task | false | false | false (blocked) |
| Task | true | * | false (done) |
| Gate (any) | * | * | **false** (auto) |

**Frontend Usage:**
- Highlights nodes user can act on
- Primary interaction targets
- Gates never highlighted as actionable

---

### 4. calculated_due

**Semantic Meaning:** "Earliest deadline affecting this node (own or downstream)."

**Calculation:**

```python
def calculate_due(node: Node, downstream_nodes: list[Node]) -> int | None:
    """Min of own due and all downstream calculated_due dates."""
    dues = []

    if node.due is not None:
        dues.append(node.due)

    for downstream in downstream_nodes:
        if downstream.calculated_due is not None:
            dues.append(downstream.calculated_due)

    return min(dues) if dues else None
```

**For ALL node types:**
- Propagates urgency upstream
- Min aggregation (earliest deadline wins)
- Works recursively through graph

**Frontend Usage:**
- Urgency-based label coloring
- Only applies when `calculated_value == false` (incomplete work)

---

## Frontend Display Logic

### Node Shape

```typescript
const shape = {
  'Task': 'square',
  'And': 'upTriangle',
  'Or': 'diamond',
  'Not': 'downTriangle',
  'ExactlyOne': 'hexagon'
}[node.node_type] || 'square';
```

### Node Fill (Hollow vs Filled)

```typescript
const hollow = !node.calculated_value;
// hollow = incomplete, filled = complete
```

### Visual States

| State | Condition | Visual |
|-------|-----------|--------|
| **Actionable Task** | `is_actionable == true` | Bright color, hollow, pulsing/highlighted |
| **Blocked Task** | `node_type == "Task" && !completed && !deps_clear` | Dim color, hollow, grayed out |
| **Complete** | `calculated_value == true` | Filled shape |
| **Gate (incomplete)** | `node_type != "Task" && !calculated_value` | Hollow shape, secondary color |
| **Gate (complete)** | `node_type != "Task" && calculated_value` | Filled shape, secondary color |

### Label Color

```typescript
let labelColor = defaultColor;

// Show urgency if incomplete and has deadline
if (!node.calculated_value && node.calculated_due) {
  labelColor = getUrgencyColorFromTimestamp(node.calculated_due);
}
```

---

## Deprecated Properties

| Property | Status | Replacement |
|----------|--------|-------------|
| `inferred` | ❌ REMOVED | Use `node_type` |
| `calculated_completed` | ❌ RENAMED | Use `calculated_value` |

---

## API Response Format

```json
{
  "tasks": {
    "task-1": {
      "id": "task-1",
      "node_type": "Task",
      "text": "Write code",
      "completed": false,
      "due": 1739145600,
      "created_at": 1739059200,
      "updated_at": 1739059200,

      "calculated_value": false,
      "calculated_due": 1739145600,
      "deps_clear": true,
      "is_actionable": true,

      "parents": ["dep-id-1"],
      "children": []
    },
    "gate-1": {
      "id": "gate-1",
      "node_type": "And",
      "text": "All prerequisites met",
      "completed": null,
      "due": null,
      "created_at": 1739059200,
      "updated_at": 1739059200,

      "calculated_value": false,
      "calculated_due": 1739145600,
      "deps_clear": false,
      "is_actionable": false,

      "parents": [],
      "children": ["dep-id-1", "dep-id-2"]
    }
  }
}
```

---

## Semantic Hierarchy

```
Graph Structure (DEPENDS_ON relationships)
    ↓
deps_clear = gate_logic(dependencies.calculated_value)
    +
own_value (completed for Task, true for Gates)
    ↓
calculated_value = own_value AND deps_clear
    ↓
is_actionable = deps_clear AND NOT own_value (Tasks only)
    ↓
Visual State (shape, color, fill, highlight)
```

**Key Relationships:**
- `deps_clear` = pure gate evaluation (ignores own state)
- `calculated_value` = combines own state with gate evaluation
- For Gates: `calculated_value == deps_clear` (no own state)
- For Tasks: `calculated_value = completed AND deps_clear`
- `is_actionable = deps_clear AND NOT completed` (Tasks only)

---

## Key Principles

1. **Gates auto-compute:** Never manually set, never actionable
2. **Tasks are interactive:** User can complete/uncomplete, but `calculated_value` still requires `deps_clear`
3. **deps_clear is gate-specific:** Each node type applies its own logic to dependencies
4. **calculated_value = own_value AND deps_clear:** Universal formula across all node types
5. **is_actionable = deps_clear AND NOT own_value:** Highlights work that can be done now (Tasks only)
6. **calculated_due propagates urgency:** Flows upstream through graph
7. **For Gates: calculated_value == deps_clear** (own_value is identity element)

---

## Implementation Checklist

### Backend (`services_new.py`)
- [x] `calculated_value` - recursive boolean logic
- [x] `calculated_due` - recursive min aggregation
- [x] `deps_clear` - all dependencies satisfied
- [x] `is_actionable` - Task + !completed + deps_clear

### API (`models_new.py`)
- [x] `NodeOut.calculated_value`
- [x] `NodeOut.calculated_due`
- [x] `NodeOut.deps_clear`
- [x] `NodeOut.is_actionable`

### Frontend (`styleGraphData.ts`)
- [ ] Use `node_type` instead of `inferred`
- [ ] Use `calculated_value` instead of `calculatedCompleted`
- [ ] Update shape logic for 5 node types
- [ ] Update actionability logic (gates never actionable)
- [ ] Remove manual `isBlocked` calculation (use `!deps_clear`)
- [ ] Add highlighting for `is_actionable` nodes
