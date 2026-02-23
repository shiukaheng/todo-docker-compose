# Client Generation Maintenance

## When to regenerate

Run `backend/repo/client/generate.sh` whenever the backend API surface changes:

- New REST endpoints added or removed
- Request/response models added, removed, or modified (fields renamed, types changed)
- Path parameters or query parameters changed
- HTTP methods changed on existing endpoints

After regenerating, rebuild and reinstall:
```bash
cd backend/repo/client && npm run build
cd ../../frontend/repo && npm install
```

## What is NOT auto-generated

The OpenAPI generator handles REST endpoints but **not** SSE (Server-Sent Events) subscriptions. These are manually maintained in `backend/repo/client/sse.ts`:

- `subscribeToState()` — connects to `GET /api/state/subscribe`
- `subscribeToDisplay()` — connects to `GET /api/display/subscribe`
- `subscribeToTasks()` — deprecated, connects to `GET /api/tasks/subscribe`

**If you add a new SSE endpoint**, you must manually add a corresponding subscription function in `sse.ts` and export it from `index.ts`.

SSE handlers parse the raw JSON and pass it through the generated `*FromJSON` deserializer functions (e.g. `AppStateFromJSON`, `ViewListOutFromJSON`). This is necessary because the SSE payload is raw JSON, not handled by the generated fetch client.

## Python → TypeScript naming conventions

The OpenAPI generator automatically converts Python's `snake_case` to TypeScript's `camelCase`:

| Python (backend models) | TypeScript (generated client) | Wire format (JSON) |
|---|---|---|
| `view_id` | `viewId` | `view_id` |
| `created_at` | `createdAt` | `created_at` |
| `from_id` | `fromId` | `from_id` |
| `has_cycles` | `hasCycles` | `has_cycles` |
| `node_type` | `nodeType` | `node_type` |

The JSON wire format stays `snake_case` (matching Python). The generated TypeScript client handles the conversion in its `*FromJSON` / `*ToJSON` functions.

**Important**: When using raw `fetch()` (bypassing the generated client), you get raw JSON with `snake_case` keys. When using the generated `DefaultApi` methods, you get `camelCase` TypeScript objects. This matters for:
- SSE handlers in `sse.ts` — they call `*FromJSON` to convert
- Direct `fetch()` calls in frontend code (e.g. position persistence) — must use `snake_case` keys when reading raw JSON

## Frontend code using raw fetch

Some frontend code bypasses the generated client and uses `fetch()` directly:

- `PositionPersistenceManager.ts` — uses `fetch(GET/PUT /api/views/{viewId}/positions)` for position load/save
- `createview.ts` fork path — uses `fetch()` to copy positions between views

When using raw `fetch()`, the JSON keys are `snake_case` (matching the backend). The response from `GET /api/views/{viewId}/positions` returns `{ "positions": { ... } }` which doesn't need conversion since `positions` is the same in both cases.

## Display SSE vs REST: what data lives where

| Data | How it's saved | How it's read | SSE broadcast? |
|---|---|---|---|
| Filter (whitelist) | `POST /api/display/batch` (update_view) | Display SSE / `GET /api/views/{id}` | Yes |
| Hide (blacklist) | `POST /api/display/batch` (update_view) | Display SSE / `GET /api/views/{id}` | Yes |
| Positions | `PUT /api/views/{id}/positions` | `GET /api/views/{id}/positions` | No |

Positions are intentionally excluded from the display SSE to avoid a feedback loop where saving positions would trigger an SSE broadcast, causing the frontend to reprocess filter/hide state.
