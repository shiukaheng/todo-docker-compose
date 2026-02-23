# View System: Frontend Control Flow & Issues

## Architecture Overview

The graph engine has three data sources that feed into rendering:

1. **Core data** — state SSE → zustand `graphData` → `engine.updateState()`
2. **View filters/topology** — display SSE → zustand `displayData` → derived `filterNodeIds`/`blacklistNodeIds` → engine store subscription
3. **Position persistence** — simulation settles → `PositionPersistenceManager` saves to server; `loadPositions()` reads from `displayData` on restore

## Current Control Flow

### Startup Sequence

```
renderer.tsx: subscribe(baseUrl)
    ├── subscribeToState(callback)       →  sets store.graphData
    └── subscribeToDisplay(callback)     →  sets store.displayData
                                             derives filterNodeIds / blacklistNodeIds

useGraphViewerEngine.ts:
    useEffect([graphData]) → engine.updateState(graphData)
```

### State SSE Update

```
State SSE event (AppState)
    │
    ▼
store.graphData = data
    │
    ▼
useEffect detects graphData change
    │
    ▼
engine.updateState(appState)
    ├── lastAppState = appState
    └── processGraphData(appState, restorePositions=!this.currentFilterNodeIds)
            ├── applyFilter(tasks, deps)          // whitelist BFS + blacklist removal
            ├── preprocessGraph(filtered)          // nest, components, base+conditional style
            ├── preprocessPlans / stylePlans       // cached, not per-frame
            └── if restorePositions:
                    restorePositionsFromStorage()
                        └── loadPositions()        // reads displayData from store
                            └── if coverage > 50%: use saved positions
                            └── else: fresh layout
```

### Display SSE Update

```
Display SSE event (ViewListOut)
    │
    ▼
deriveViewFilters(data, currentViewId)
    └── extracts whitelist/blacklist from views[currentViewId]
    │
    ▼
store.set({ displayData, filterNodeIds, blacklistNodeIds })
    │
    ▼
engine store subscription detects changes:
    ├── currentViewId changed?  → onViewChange()
    ├── filterNodeIds changed?  → onFilterChange()
    └── blacklistNodeIds changed? → processGraphData(lastAppState, false)
```

### View Switch

```
switchView(viewId)
    │
    ▼
store.set({ currentViewId, filterNodeIds, blacklistNodeIds })
    │                          (derived from new view)
    ▼
engine subscription detects currentViewId change
    │
    ▼
onViewChange(prevViewId, newFilter, newBlacklist)
    ├── savePositionsNow(prevViewId)       // persist old view's positions
    ├── update filter/blacklist state
    ├── updatePersistencePause()
    └── processGraphData(lastAppState, restorePositions=true)
            └── restorePositionsFromStorage()
                    └── loadPositions() reads store.displayData.views[newViewId]
    │
    ▼
this.currentViewId = nextViewId            // updated AFTER onViewChange returns
```

### Filter Change (whitelist)

```
onFilterChange(prevFilter, newFilter)
    ├── if activating (null → non-null): savePositionsNow()
    ├── updatePersistencePause()
    └── processGraphData(lastAppState, restorePositions=(newFilter === null))
```

### Position Persistence (save path)

```
PositionPersistenceManager polling (every 1s)
    │
    ▼
checkPositions()
    ├── compare current vs last positions
    ├── if movement < 0.5 units: settled
    └── on unsettled→settled transition:
            scheduleSave()  (debounced 2s)
                └── savePositionsNow()
                        └── api.displayBatch({ op: 'update_view', positions })
                                │
                                ▼
                        server broadcasts display SSE
                        (triggers display SSE update flow above)
```

### Animation Loop (per frame, 60fps)

```
requestAnimationFrame(tick)
    ├── 1. simulationEngine.step()         → new positions
    ├── 2. mergePositions()                → attach positions to task data
    ├── 3. updateCursorNeighbors()         → topological neighbor computation
    ├── 4. cursorStyleGraphData()          → selector outline on cursor
    │      navigationStyleGraphData()      → shortcut key overlays on neighbors
    ├── 5. navigationEngine.step()         → viewport transform (pan/zoom)
    ├── 6. interactionController.update()  → drag momentum
    └── 7. renderer.render()               → SVG DOM update
```

## Issues

### Issue 1: Startup Race — Positions Lost on Load (critical)

**Location**: `useGraphViewerEngine.ts:64-69`, `PositionPersistenceManager.ts:111-137`

State SSE and display SSE are independent streams started simultaneously. If state SSE arrives first (likely), the engine calls `updateState()` → `processGraphData(true)` → `restorePositionsFromStorage()` → `loadPositions()`, which reads `displayData` from the store.

But `displayData` is still `null` because display SSE hasn't arrived yet. `loadPositions()` returns `{}`, coverage is 0%, and the engine starts a fresh layout.

When display SSE finally arrives, it sets `displayData` with the correct positions, but nothing triggers the engine to re-read them:
- If the view has no whitelist/blacklist: `filterNodeIds` stays `null`, no change detected, no reprocessing.
- Even if a filter IS detected, `onFilterChange` only restores positions when `newFilter === null` (clearing), not when activating.

**Result**: Saved view positions are silently discarded on every app startup.

### Issue 2: Reference Equality on Filter Arrays — Spurious Reprocessing (medium)

**Location**: `GraphViewerEngine.ts:160`, `todoStore.ts:243-265`

Every display SSE update calls `deriveViewFilters()`, which creates new array objects:

```javascript
return {
    filterNodeIds: viewData.whitelist?.length ? viewData.whitelist : null,
    blacklistNodeIds: viewData.blacklist?.length ? viewData.blacklist : null,
};
```

The engine checks with reference comparison:

```javascript
if (state.filterNodeIds !== this.currentFilterNodeIds) {
```

New arrays with identical content fail `!==`, triggering `onFilterChange()` and full graph reprocessing on every display SSE event, even when nothing actually changed.

### Issue 3: Position Save → Display SSE Feedback Loop (high)

**Location**: Interaction between `PositionPersistenceManager`, display SSE subscription, and engine store subscription.

The cycle:

1. Graph settles → `savePositionsNow()` sends positions to server
2. Server updates view → broadcasts display SSE
3. Display SSE callback → `deriveViewFilters()` creates new filter arrays (issue 2)
4. Engine detects "filter change" → `onFilterChange()` → `processGraphData()` reprocesses graph
5. Simulation potentially disturbed → new settle cycle → back to step 1

Every position save triggers unnecessary full graph reprocessing.

### Issue 4: Stale `this.currentViewId` During `onViewChange` (low, fragile)

**Location**: `GraphViewerEngine.ts:143-158`

```javascript
if (state.currentViewId !== this.currentViewId) {
    this.onViewChange(prevViewId, nextFilter, nextBlacklist);
    this.currentViewId = nextViewId;   // updated AFTER onViewChange
}
```

Inside `onViewChange`, `loadPositions()` reads `currentViewId` from the zustand store (already updated), not from `this.currentViewId` (still old). This works by accident — the load path depends on the store update happening synchronously before the subscription fires. The save path correctly uses `prevViewId` passed as an explicit argument. The asymmetry is fragile.

### Issue 5: Blacklist Doesn't Pause Position Persistence (medium)

**Location**: `GraphViewerEngine.ts:407-414`

```javascript
private updatePersistencePause(): void {
    const shouldPause = this.currentFilterNodeIds !== null;
    this.positionPersistence.setPaused(shouldPause);
}
```

Only whitelist pauses persistence. With a blacklist active (hiding nodes), the simulation state contains only visible nodes, but positions are saved back to the view. This overwrites the full position set with a partial one — hidden nodes lose their saved positions.
