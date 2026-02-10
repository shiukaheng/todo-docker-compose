# Frontend Update Plan - Boolean Graph Implementation

**Date:** 2026-02-10
**Status:** Ready for implementation

## Overview

Update the frontend to support the new boolean graph backend with 5 node types (Task, And, Or, Not, ExactlyOne) instead of the binary inferred/regular task system.

## Agent Exploration Summary

Four background agents explored the codebase:
1. **Rendering logic** - Shape system, visual properties
2. **Node panel UI** - Edit fields, toggle mechanisms
3. **Commands/actions** - All command definitions and keyboard shortcuts
4. **API client** - Type definitions, response parsing, OpenAPI generation

## Core Changes Required

### 1. API Type Updates

**Priority:** HIGH (blocks everything)
**Complexity:** Medium
**Files:** Generated TypeScript client

#### Current API Response
```typescript
interface TaskOut {
    inferred: boolean;                    // OLD - boolean flag
    calculatedCompleted: boolean | null;  // OLD - renamed
    // ... other fields
}
```

#### New API Response
```typescript
interface NodeOut {
    node_type: "Task" | "And" | "Or" | "Not" | "ExactlyOne";  // NEW
    calculated_value: boolean | null;     // NEW - renamed from calculatedCompleted
    deps_clear: boolean | null;           // ENHANCED - gate-specific now
    is_actionable: boolean | null;        // NEW - backend calculated
    completed: boolean | null;            // MODIFIED - null for gates
    // ... other fields
}
```

#### Action Items
- [ ] **Regenerate API client** from updated OpenAPI schema
  - Path: `/backend/repo/client/openapi.json` → TypeScript client
  - Run: `cd backend/repo/client && ./generate.sh` (or equivalent)
  - Updates: `node_modules/todo-client/client/generated/`

- [ ] **Add backward compatibility layer** during transition
  ```typescript
  // In preprocessing pipeline
  const node_type = data.node_type || (data.inferred ? "And" : "Task");
  const calculated_value = data.calculated_value ?? data.calculatedCompleted;
  ```

---

### 2. Rendering Updates

**Priority:** HIGH
**Complexity:** Medium
**Files:**
- `/frontend/repo/src/graph/render/utils.ts`
- `/frontend/repo/src/graph/render/SVGRenderer.ts`
- `/frontend/repo/src/graph/preprocess/styleGraphData.ts`

#### 2.1 Add New Shape Types

**File:** `/frontend/repo/src/graph/render/utils.ts:22`

```typescript
// OLD
export type NodeShape = 'square' | 'upTriangle';

// NEW
export type NodeShape = 'square' | 'upTriangle' | 'downTriangle' | 'circle' | 'triangleCircle';
```

#### 2.2 Implement New Shape Renderers

**File:** `/frontend/repo/src/graph/render/SVGRenderer.ts:269-290`

Currently renders:
- `square` - Regular tasks
- `upTriangle` - AND gates (inferred tasks)

Need to add:
- `downTriangle` - OR gates (upside down triangle)
- `circle` - ExactlyOne gates
- `triangleCircle` - NOT gates (triangle with circle)

**Implementation:**

```typescript
// In SVGRenderer.ts renderNode() method, add after line 282:

else if (node.shape === 'downTriangle') {
    // Inverted equilateral triangle (OR gate)
    const side = size;
    const h = side * Math.sqrt(3) / 2;
    const topY = y - h / 2;
    const bottomY = y + h / 2;
    const leftX = x - side / 2;
    const rightX = x + side / 2;
    // Flip: bottom vertex at top, top vertices at bottom
    pathD = `M ${x} ${bottomY} L ${rightX} ${topY} L ${leftX} ${topY} Z`;
}
else if (node.shape === 'circle') {
    // Circle (ExactlyOne gate)
    const radius = halfSize;
    // Use SVG circle element or path with arcs
    pathD = `M ${x - radius} ${y} A ${radius} ${radius} 0 1 0 ${x + radius} ${y} A ${radius} ${radius} 0 1 0 ${x - radius} ${y} Z`;
}
else if (node.shape === 'triangleCircle') {
    // Triangle with circle overlay (NOT gate)
    // Render as upTriangle with circle stroke
    const side = size;
    const h = side * Math.sqrt(3) / 2;
    const topY = y - h / 2;
    const bottomY = y + h / 2;
    const leftX = x - side / 2;
    const rightX = x + side / 2;
    const radius = halfSize * 0.6;  // Smaller circle inside
    pathD = `M ${x} ${topY} L ${rightX} ${bottomY} L ${leftX} ${bottomY} Z M ${x - radius} ${y} A ${radius} ${radius} 0 1 0 ${x + radius} ${y} A ${radius} ${radius} 0 1 0 ${x - radius} ${y} Z`;
}
```

#### 2.3 Update Shape Assignment Logic

**File:** `/frontend/repo/src/graph/preprocess/styleGraphData.ts:213-231`

**Current logic:**
```typescript
const isInferred = data.inferred;
const shape: NodeShape = isInferred ? 'upTriangle' : 'square';
```

**New logic:**
```typescript
const nodeType = data.node_type || (data.inferred ? "And" : "Task");
const shape: NodeShape = {
    'Task': 'square',
    'And': 'upTriangle',
    'Or': 'downTriangle',
    'Not': 'triangleCircle',
    'ExactlyOne': 'circle'
}[nodeType] || 'square';
```

#### 2.4 Remove Redundant Calculations

**File:** `/frontend/repo/src/graph/preprocess/styleGraphData.ts:200-255`

**Lines to REMOVE (backend now provides these):**
- Lines 201-206: Manual `taskCalcCompleted` map building
- Lines 215-228: Manual `isBlocked`, `isCompleted`, `isActionable` calculations

**Keep from backend:**
```typescript
const isBlocked = !data.deps_clear;                    // Backend provides this
const isCompleted = data.calculated_value === true;    // Backend provides this
const isActionable = data.is_actionable === true;      // Backend provides this
```

**Simplified logic:**
```typescript
const data = task.data as {
    node_type?: string;
    calculated_value?: boolean;
    deps_clear?: boolean;
    is_actionable?: boolean;
    calculatedDue?: number | null;
};

const nodeType = data.node_type || "Task";
const shape: NodeShape = SHAPE_MAP[nodeType] || 'square';
const hollow = !(data.calculated_value === true);

// Label color: urgency-based if has due and incomplete
let labelColor: Color = [1, 1, 1];
if (data.calculatedDue && !data.calculated_value) {
    labelColor = getUrgencyColorFromTimestamp(data.calculatedDue);
}

let styledTask = { ...task, shape, hollow, labelColor };

// Blocked: dim the node
if (!data.deps_clear) {
    return [taskId, { ...styledTask, brightnessMultiplier: 0.1 }];
}
// Actionable: highlight (could add special styling)
if (data.is_actionable) {
    return [taskId, { ...styledTask, /* add highlighting */ }];
}
return [taskId, styledTask];
```

---

### 3. Node Detail Overlay Updates

**Priority:** HIGH
**Complexity:** Medium
**File:** `/frontend/repo/src/graph/NodeDetailOverlay.tsx`

#### 3.1 Remove Redundant isBlocked Calculation

**Lines 22-35:** DELETE this calculation (backend provides `deps_clear`)

```typescript
// OLD (lines 22-35)
const isBlocked = (() => {
    if (!task || !graphData) return false;
    const childDepIds = task.children || [];
    // ... manual calculation
})();

// NEW
const isBlocked = task ? !task.deps_clear : false;
```

#### 3.2 Add Node Type Selector

**Lines 255-261:** Replace inferred toggle with node type dropdown

**Current:**
```typescript
{/* Node type: task or inferred - click to toggle */}
<div onClick={toggleInferred} className="...">
    {task.inferred ? "inferred" : "task"}
</div>
```

**New:**
```typescript
{/* Node type selector */}
<div className="flex items-center gap-2">
    <span className="text-white/50 font-mono text-xs">type:</span>
    <select
        value={task.node_type || "Task"}
        onChange={(e) => {
            if (!api || !task) return;
            api.setTaskApiTasksTaskIdPatch({
                taskId: task.id,
                taskUpdate: { node_type: e.target.value }
            });
        }}
        className="bg-white/10 text-white font-mono text-xs border-0 rounded px-2 py-1"
    >
        <option value="Task">task</option>
        <option value="And">and (all)</option>
        <option value="Or">or (any)</option>
        <option value="Not">not (none)</option>
        <option value="ExactlyOne">xor (one)</option>
    </select>
</div>
```

#### 3.3 Disable Completed Toggle for Gates

**Lines 125-137:** Add node type check

```typescript
// OLD
const canToggle = task && !task.inferred && !isBlocked;

// NEW
const canToggle = task && task.node_type === "Task" && !isBlocked;
```

#### 3.4 Update Property Names

**Multiple locations:** Replace old field names with new ones
- `task.calculatedCompleted` → `task.calculated_value`
- `task.inferred` → `task.node_type !== "Task"`
- Add `task.is_actionable` display (optional)

---

### 4. Command Updates

**Priority:** MEDIUM
**Complexity:** Low
**Files:** `/frontend/repo/src/commander/commands/*.ts`

#### 4.1 Add Node Type to Create Commands

**Files:**
- `/frontend/repo/src/commander/commands/add.ts`
- `/frontend/repo/src/commander/commands/addblock.ts`
- `/frontend/repo/src/commander/commands/adddep.ts`

**Add `--type` option:**

```typescript
// In add.ts, adddep.ts, addblock.ts
options: [
    {
        name: 'text',
        short: 't',
        type: 'string',
        description: 'Task description text',
    },
    {
        name: 'type',
        short: 'y',
        type: 'string',
        description: 'Node type: task, and, or, not, xor (default: task)',
        default: 'task',
    },
    // ... other options
]
```

**Use in handler:**

```typescript
const nodeTypeMap: Record<string, string> = {
    'task': 'Task',
    'and': 'And',
    'or': 'Or',
    'not': 'Not',
    'xor': 'ExactlyOne',
    'exactlyone': 'ExactlyOne',
};

const node_type = nodeTypeMap[args.options.type?.toLowerCase() || 'task'] || 'Task';

await api.addTaskApiTasksPost({
    taskCreate: {
        id: taskId,
        text: args.options.text || null,
        node_type: node_type,  // NEW
        completed: args.options.completed || false,
        // ...
    }
});
```

#### 4.2 Add Toggle Completed Validation

**New command:** `/frontend/repo/src/commander/commands/toggle.ts`

```typescript
import { CommandDefinition } from '../types';
import { useTodoStore } from '../../stores/todoStore';
import { output } from '../output';

export const toggleCommand: CommandDefinition = {
    name: 'toggle',
    description: 'Toggle task completion (space key equivalent)',
    aliases: ['t', 'done'],
    handler: async () => {
        const { cursor, graphData, api } = useTodoStore.getState();
        if (!cursor) {
            output.error('no cursor - navigate to a task first');
            return;
        }
        if (!api) {
            output.error('not connected to server');
            return;
        }
        const task = graphData?.tasks?.[cursor];
        if (!task) {
            output.error(`task not found: ${cursor}`);
            return;
        }

        // Validate: only Tasks can be toggled
        if (task.node_type && task.node_type !== 'Task') {
            output.error(`cannot toggle ${task.node_type} gate - only tasks can be completed manually`);
            return;
        }

        // Check if blocked
        if (!task.deps_clear) {
            output.error('task is blocked - complete dependencies first');
            return;
        }

        try {
            await api.setTaskApiTasksTaskIdPatch({
                taskId: task.id,
                taskUpdate: { completed: !task.completed },
            });
            output.success(task.completed ? 'marked incomplete' : 'marked complete');
        } catch (err) {
            output.error(`failed to toggle: ${err}`);
        }
    },
};
```

#### 4.3 Update Command Registration

**File:** `/frontend/repo/src/commander/commands/index.ts`

```typescript
import { toggleCommand } from './toggle';

export function registerBuiltinCommands(registry: CommandRegistry) {
    // ... existing commands
    registry.register(toggleCommand);
}
```

---

### 5. Keyboard Shortcuts Update

**Priority:** LOW
**Complexity:** Low
**File:** `/frontend/repo/src/shortcuts/ActionProvider.tsx` or `/frontend/repo/src/graph/GraphViewer.tsx`

**Current:** Space key directly toggles completion in NodeDetailOverlay

**New:** Add validation before toggle (check node_type)

```typescript
// In NodeDetailOverlay.tsx handleToggleCompleted (line 127-138)
const handleToggleCompleted = useCallback(async () => {
    if (!task || !api) return;

    // NEW: Validate node type
    if (task.node_type && task.node_type !== "Task") {
        console.warn(`Cannot toggle ${task.node_type} gate`);
        return;
    }

    if (!task.deps_clear) {
        console.warn('Task is blocked');
        return;
    }

    // Proceed with toggle
    await api.setTaskApiTasksTaskIdPatch({
        taskId: task.id,
        taskUpdate: { completed: !task.completed },
    });
}, [task, api]);
```

---

## Implementation Order

### Phase 1: API & Type Updates (Blocks everything)
1. Update backend `models.py` to use `node_type` (✅ DONE)
2. Update backend `services.py` with new calculations (✅ DONE)
3. Regenerate OpenAPI spec from backend
4. Regenerate TypeScript API client
5. Add backward compatibility layer in frontend preprocessing

### Phase 2: Visual Updates (Independent)
6. Add new shape types to `utils.ts`
7. Implement shape renderers in `SVGRenderer.ts`
8. Update shape assignment logic in `styleGraphData.ts`
9. Remove redundant calculations from `styleGraphData.ts`

### Phase 3: UI Updates (Depends on Phase 1)
10. Update `NodeDetailOverlay.tsx` with node type selector
11. Remove redundant `isBlocked` calculation
12. Add validation to completed toggle
13. Update all property references (inferred → node_type, etc.)

### Phase 4: Command Updates (Depends on Phase 1)
14. Add `--type` option to create commands
15. Create toggle command with validation
16. Register new command

### Phase 5: Testing & Polish
17. Test all 5 node types rendering correctly
18. Test node type switching in UI
19. Test command creation with different types
20. Test that gates can't be manually completed
21. Verify urgency colors work
22. Test actionable highlighting

---

## Testing Checklist

### Visual Rendering
- [ ] Task nodes show as squares
- [ ] And gates show as up triangles
- [ ] Or gates show as down triangles
- [ ] Not gates show as triangle+circle
- [ ] ExactlyOne gates show as circles
- [ ] Hollow/filled states work for all shapes
- [ ] Urgency colors apply correctly

### Node Panel
- [ ] Node type dropdown shows all 5 types
- [ ] Changing type updates shape immediately
- [ ] Completed toggle disabled for gates
- [ ] Space key disabled for gates
- [ ] `is_actionable` status displayed
- [ ] Field names updated (no "inferred", "calculatedCompleted")

### Commands
- [ ] `add --type and` creates And gate
- [ ] `add --type or` creates Or gate
- [ ] `add --type not` creates Not gate
- [ ] `add --type xor` creates ExactlyOne gate
- [ ] `toggle` command validates node type
- [ ] `toggle` shows error for gates

### Calculations
- [ ] No manual `isBlocked` calculations
- [ ] Backend `deps_clear` used directly
- [ ] Backend `calculated_value` used for completion
- [ ] Backend `is_actionable` used for highlighting
- [ ] Gate-specific `deps_clear` logic works (Or with one true = not blocked)

### Edge Cases
- [ ] Empty graph renders
- [ ] Single isolated gate renders
- [ ] Mixed graphs (Tasks + Gates) render
- [ ] Converting Task → Gate removes completed flag
- [ ] Converting Gate → Task adds completed flag
- [ ] Cycles detected and handled

---

## Rollback Plan

If issues arise:

1. **Revert API client generation:**
   ```bash
   cd frontend/repo
   git checkout node_modules/todo-client/
   npm install  # Reinstall clean version
   ```

2. **Re-enable backward compatibility:**
   ```typescript
   // Keep both old and new field support
   const inferred = data.inferred ?? (data.node_type !== "Task");
   const calculatedCompleted = data.calculatedCompleted ?? data.calculated_value;
   ```

3. **Disable new shapes temporarily:**
   ```typescript
   // Map all gates to upTriangle until rendering fixed
   const shape = nodeType === "Task" ? "square" : "upTriangle";
   ```

---

## Files Modified Summary

| File | Change Type | Lines | Priority |
|------|-------------|-------|----------|
| `backend/repo/client/openapi.json` | Generated | N/A | HIGH |
| `frontend/repo/node_modules/todo-client/` | Generated | N/A | HIGH |
| `frontend/repo/src/graph/render/utils.ts` | Edit | ~5 | HIGH |
| `frontend/repo/src/graph/render/SVGRenderer.ts` | Add | ~50 | HIGH |
| `frontend/repo/src/graph/preprocess/styleGraphData.ts` | Edit/Remove | ~30 | HIGH |
| `frontend/repo/src/graph/NodeDetailOverlay.tsx` | Edit | ~40 | HIGH |
| `frontend/repo/src/commander/commands/add.ts` | Edit | ~10 | MEDIUM |
| `frontend/repo/src/commander/commands/addblock.ts` | Edit | ~10 | MEDIUM |
| `frontend/repo/src/commander/commands/adddep.ts` | Edit | ~10 | MEDIUM |
| `frontend/repo/src/commander/commands/toggle.ts` | Create | ~60 | MEDIUM |
| `frontend/repo/src/commander/commands/index.ts` | Edit | ~2 | MEDIUM |

**Total:** ~11 files, ~217 lines modified/added

---

## Estimated Timeline

| Phase | Time Estimate |
|-------|---------------|
| Phase 1: API & Types | 1-2 hours |
| Phase 2: Visual Updates | 2-3 hours |
| Phase 3: UI Updates | 1-2 hours |
| Phase 4: Command Updates | 1 hour |
| Phase 5: Testing | 2-3 hours |
| **Total** | **7-11 hours** |

---

## Notes

- **Backward compatibility:** Keep for 1-2 releases, then remove
- **OpenAPI generation:** Document the regeneration process
- **Shape designs:** Consider user feedback on NOT gate (triangle+circle) design
- **Actionable highlighting:** Could add pulse animation or brighter color
- **Type validation:** Backend should also validate (don't rely on frontend only)

---

**Last Updated:** 2026-02-10
**Plan Version:** 1.0
