# Semantic Corrections - Boolean Graph Properties

## Summary of Changes

Fixed the calculation of `calculated_value` and `deps_clear` to match the correct semantic model.

## The Correct Model

### Universal Formula

**`calculated_value = own_value AND deps_clear`**

Where:
- **own_value**: Task = `completed`, Gates = `true` (identity element)
- **deps_clear**: Gate-specific evaluation of dependencies (ignores own state)

### Key Insight

**deps_clear is gate-specific**, not universal AND logic!

| Node Type | deps_clear Calculation |
|-----------|------------------------|
| Task | `all(deps.calculated_value)` - AND logic |
| And | `all(deps.calculated_value)` - AND logic |
| Or | `any(deps.calculated_value)` - OR logic |
| Not | `!(any(deps.calculated_value))` - NOR logic |
| ExactlyOne | `sum(deps.calculated_value) == 1` - XOR logic |

## What Was Wrong

### Old Implementation

```python
# calculated_value - WRONG for Task
if node.node_type == "Task":
    return node.completed  # ❌ Ignores dependencies!

# deps_clear - WRONG for all nodes
deps_clear = all(deps.calculated_value)  # ❌ Always AND logic
```

### New Implementation

```python
# calculated_value - CORRECT
def calculate_value(node_id):
    dep_values = [calculate_value(dep_id) for dep_id in deps]
    deps_clear = calculate_gate_logic(node.node_type, dep_values)

    if node.node_type == "Task":
        return node.completed and deps_clear  # ✓ Combines own state with deps
    else:
        return deps_clear  # ✓ Gates have no own state

# deps_clear - CORRECT
def calculate_deps_clear(node_id):
    dep_values = [calculate_value(dep_id) for dep_id in deps]
    return calculate_gate_logic(node.node_type, dep_values)  # ✓ Gate-specific

# Gate logic - unified function
def calculate_gate_logic(node_type, dep_values):
    if node_type in ["Task", "And"]:
        return not dep_values or all(dep_values)
    elif node_type == "Or":
        return bool(dep_values) and any(dep_values)
    elif node_type == "Not":
        return not any(dep_values)
    elif node_type == "ExactlyOne":
        return sum(dep_values) == 1
```

## Why This Matters

### 1. Task Consistency Enforcement

**Old:** Task `completed=true` → `calculated_value=true` (always)

**New:** Task `completed=true` but `deps_clear=false` → `calculated_value=false`

This enforces logical consistency: "You can't complete a task if its prerequisites aren't met."

### 2. Gate-Specific deps_clear

**Old:** `deps_clear` always used AND logic for all nodes

**New:** `deps_clear` respects each node's gate type:
- Or gate: `deps_clear=true` when ANY dep is true (not ALL)
- Not gate: `deps_clear=true` when NO deps are true
- ExactlyOne: `deps_clear=true` when EXACTLY ONE dep is true

This allows the UI to show meaningful "blocked" states for different gate types.

### 3. Semantic Clarity

The formula `calculated_value = own_value AND deps_clear` is now universal:

| Node Type | own_value | deps_clear | calculated_value |
|-----------|-----------|------------|------------------|
| Task | `completed` | `all(deps)` | `completed AND all(deps)` |
| And | `true` | `all(deps)` | `all(deps)` |
| Or | `true` | `any(deps)` | `any(deps)` |
| Not | `true` | `!(any(deps))` | `!(any(deps))` |
| ExactlyOne | `true` | `sum(deps)==1` | `sum(deps)==1` |

Gates have `own_value = true` (identity), so `calculated_value = deps_clear` for gates.

## Example Scenarios

### Scenario 1: Task with Incomplete Dependencies

```
Task "Deploy" (completed=true)
  ├─ Dep: "Tests" (calculated_value=false)
  └─ Dep: "Review" (calculated_value=true)

Old behavior:
  calculated_value = true  (just checks completed flag)

New behavior:
  deps_clear = all([false, true]) = false
  calculated_value = true AND false = false  ✓ Logically incomplete
```

### Scenario 2: Or Gate

```
Or "Any deployment method"
  ├─ Dep: "Docker" (calculated_value=true)
  └─ Dep: "K8s" (calculated_value=false)

Old behavior:
  deps_clear = all([true, false]) = false  ❌ Wrong! Or should be satisfied

New behavior:
  deps_clear = any([true, false]) = true  ✓ Correct Or logic
  calculated_value = deps_clear = true  ✓
```

### Scenario 3: Not Gate (Blockers)

```
Not "No blockers"
  ├─ Dep: "Blocker-1" (calculated_value=false)
  └─ Dep: "Blocker-2" (calculated_value=false)

Old behavior:
  deps_clear = all([false, false]) = false  ❌ Wrong! Not should be true

New behavior:
  deps_clear = !(any([false, false])) = true  ✓ No blockers active
  calculated_value = deps_clear = true  ✓
```

## Files Updated

1. **backend/repo/backend/app/core/services_new.py**
   - Renamed `_apply_gate_logic` → `_calculate_gate_logic`
   - Added Task to gate logic (uses AND)
   - Updated `_build_value_calculator` to compute `calculated_value = own_value AND deps_clear`
   - Updated `list_nodes` and `get_node` to calculate gate-specific `deps_clear`

2. **NODE_PROPERTIES_REFERENCE.md**
   - Updated `calculated_value` section with correct formula
   - Updated `deps_clear` section to show gate-specific logic
   - Updated truth tables and examples
   - Added "Inconsistent Task" scenario explanation

3. **BOOLEAN_GRAPH_SCHEMA.md**
   - Updated Node Value table with formula
   - Updated Actionability section with correct semantics
   - Added computed properties formula section

## Verification

To verify the fix is working:

```python
# Test Case 1: Task with incomplete deps
task = Task(id="t1", completed=True)
dep1 = Task(id="d1", completed=False)
# Expected: calculated_value = False (completed AND deps_clear = True AND False)

# Test Case 2: Or gate with one true
or_gate = Or(id="o1")
dep1 = Task(id="d1", completed=True)
dep2 = Task(id="d2", completed=False)
# Expected: calculated_value = True (any([True, False]) = True)

# Test Case 3: Not gate with all false
not_gate = Not(id="n1")
dep1 = Task(id="d1", completed=False)
dep2 = Task(id="d2", completed=False)
# Expected: calculated_value = True (!(any([False, False])) = True)
```
