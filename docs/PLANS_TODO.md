# Plans Feature Implementation TODO

## Backend ✅ COMPLETE

### 1. Schema & Models (`backend/app/models.py`) ✅
- [x] Add `StepData` model
  - `node_id: str`
  - `order: float`
- [x] Add `PlanCreate` model
  - `id: str`
  - `text: str | None`
  - `steps: list[StepData] = []`
- [x] Add `PlanUpdate` model
  - `text: str | None`
  - `steps: list[StepData] | None`
- [x] Add `PlanOut` model
  - `id: str`
  - `text: str | None`
  - `created_at: int`
  - `updated_at: int`
  - `steps: list[StepData]`
- [x] Add `PlanListOut` model
  - `plans: dict[str, PlanOut]`
- [x] Add `AppState` model (replaces TaskListOut for subscriptions)
  - `tasks: dict[str, TaskOut]`
  - `dependencies: dict[str, DependencyOut]`
  - `has_cycles: bool`
  - `plans: dict[str, PlanOut]`

### 2. Services (`backend/app/core/services.py`) ✅
- [x] Add `Plan` dataclass
  - `id: str`
  - `text: str | None`
  - `created_at: int`
  - `updated_at: int`
- [x] Add `Step` dataclass
  - `id: str`
  - `order: float`
  - `node_id: str`
- [x] Add plan CRUD functions:
  - [x] `list_plans(tx) -> list[Plan]` - Get all plans with their steps
  - [x] `get_plan(tx, plan_id: str) -> Plan | None` - Get single plan
  - [x] `create_plan(tx, id: str, text: str | None, steps: list[tuple[str, float]]) -> Plan`
  - [x] `update_plan(tx, id: str, text: str | None, steps: list[tuple[str, float]] | None) -> bool`
  - [x] `delete_plan(tx, id: str) -> bool`
- [x] Helper functions:
  - [x] `_get_plan_steps(tx, plan_id: str) -> list[Step]` - Get steps for a plan (ordered)
  - [x] `_set_plan_steps(tx, plan_id: str, steps: list[tuple[str, float]])` - Replace all steps

### 3. Database Constraints (`backend/app/core/services.py` - `init_db`) ✅
- [x] Add plan ID uniqueness constraint
  ```cypher
  CREATE CONSTRAINT plan_id_unique IF NOT EXISTS
  FOR (p:Plan) REQUIRE p.id IS UNIQUE;
  ```
- [x] Add STEP relationship ID uniqueness constraint
  ```cypher
  CREATE CONSTRAINT step_id_unique IF NOT EXISTS
  FOR ()-[r:STEP]->() REQUIRE r.id IS UNIQUE;
  ```

### 4. API Routes (`backend/app/api/routes.py`) ✅
- [x] Add plan endpoints:
  - [x] `GET /plans` -> `PlanListOut` - List all plans
  - [x] `GET /plans/{plan_id}` -> `PlanOut` - Get single plan
  - [x] `POST /plans` -> `PlanOut` - Create plan
  - [x] `PATCH /plans/{plan_id}` -> `PlanOut` - Update plan
  - [x] `DELETE /plans/{plan_id}` -> `OperationResult` - Delete plan
- [x] Update state endpoints:
  - [x] Add `/state/subscribe` (kept `/tasks/subscribe` for backward compat with deprecation warning)
  - [x] Update SSE to send `AppState` (tasks + dependencies + has_cycles + plans)
  - [x] Add `GET /state` endpoint for one-shot state fetch
- [x] All `await publisher.broadcast()` calls already include plan data automatically

### 5. SSE Publisher (`backend/app/api/sse.py`) ✅
- [x] Update `publisher.broadcast()` to fetch and include plan data
- [x] Change event data structure to `AppState` format

## Frontend

### 6. Generated Client
- [ ] Regenerate TypeScript client from updated OpenAPI spec
  - Should include new `PlanOut`, `PlanListOut`, `AppState` types
  - Should include new `/plans/*` endpoints
  - Should include updated `/state/subscribe` endpoint

### 7. Store (`frontend/src/stores/todoStore.ts`)
- [ ] Update `graphData` type from `NodeListOut` to `AppState`
- [ ] Update `subscribe()` to use `/state/subscribe` instead of `/tasks/subscribe`
- [ ] Add plan-specific state if needed
- [ ] Update all references to `graphData.tasks`, `graphData.dependencies`, etc.

### 8. Plan UI Components
- [ ] Create `PlanList` component - show all plans
- [ ] Create `PlanView` component - show single plan with ordered steps
- [ ] Create `PlanEditor` component - create/edit plans
- [ ] Add plan visualization mode (separate from graph view?)

### 9. Commands (`frontend/src/commander/commands/`)
- [ ] `plan create <id> [text]` - Create new plan
- [ ] `plan delete <id>` - Delete plan
- [ ] `plan list` - List all plans
- [ ] `plan view <id>` - View plan details
- [ ] `plan add-step <plan-id> <node-id> <order>` - Add step to plan
- [ ] `plan remove-step <plan-id> <order>` - Remove step from plan
- [ ] `plan edit <id>` - Edit plan text

### 10. Plan API Client Methods
- [ ] Add plan methods to API client or create separate plan service
- [ ] `api.listPlans()`
- [ ] `api.getPlan(id)`
- [ ] `api.createPlan(data)`
- [ ] `api.updatePlan(id, data)`
- [ ] `api.deletePlan(id)`

## Testing

### 11. Backend Tests
- [ ] Test plan CRUD operations
- [ ] Test step ordering (including float insertion)
- [ ] Test plan deletion (verify nodes are not deleted)
- [ ] Test constraints (unique IDs, etc.)
- [ ] Test state subscription includes plans
- [ ] Test invalid node_id in steps (should fail gracefully)

### 12. Frontend Tests
- [ ] Test plan list rendering
- [ ] Test plan view with ordered steps
- [ ] Test plan creation/update
- [ ] Test state subscription updates plans
- [ ] Test commands work correctly

## Documentation

### 13. API Documentation
- [ ] Update OpenAPI spec with new endpoints
- [ ] Document plan endpoints in API docs
- [ ] Update SSE documentation for new `/state/subscribe` format

### 14. User Documentation
- [ ] Add plan usage guide
- [ ] Document plan commands
- [ ] Add examples of plan workflows
- [ ] Update schema.md (already done ✅)

## Migration & Compatibility

### 15. Backward Compatibility
- [ ] Decide: keep `/tasks/subscribe` as alias to `/state/subscribe`?
- [ ] If yes, add deprecation warning
- [ ] Update client library to use new endpoint

### 16. Database Migration
- [ ] No migration needed (plans are new, empty table)
- [ ] Verify constraints are created on init

## Nice-to-Haves (Future)

- [ ] Plan templates
- [ ] Plan duplication
- [ ] Plan progress indicators (X of Y steps complete)
- [ ] Plan due dates (inherited from steps)
- [ ] Nested plan visualization
- [ ] Bulk step reordering
- [ ] Plan sharing/export
- [ ] Plan archiving

---

## Implementation Order

### Phase 1: Backend Core (Essential)
1. Models (§1)
2. Services (§2)
3. Constraints (§3)
4. API Routes (§4)

### Phase 2: State Subscription (Critical)
5. SSE Publisher (§5)
6. State endpoint

### Phase 3: Frontend Integration (Essential)
7. Regenerate client (§6)
8. Update store (§7)

### Phase 4: UI & Commands (User-facing)
9. Plan UI components (§8)
10. Commands (§9)
11. Client methods (§10)

### Phase 5: Quality & Docs (Polish)
12. Backend tests (§11)
13. Frontend tests (§12)
14. Documentation (§13-14)
15. Migration (§15-16)
