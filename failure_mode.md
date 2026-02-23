# ViewOut Schema Mismatch - Failure Mode & Resolution

## Problem Summary

The TypeScript client was out of sync with the backend API response. The raw API endpoint was returning view data with fields that the generated TypeScript client types didn't recognize or parse.

## Failure Mode

### What the user observed:
1. Raw API endpoint `/api/display/subscribe` returned:
```json
{
  "views": {
    "todo-app": {
      "id": "todo-app",
      "include_recursive": ["todo-app"],
      "exclude_recursive": [],
      "hide_completed_for": null,
      "created_at": 1771803036,
      "updated_at": 1771813921
    }
  }
}
```

2. But the TypeScript client's `ViewOut` interface only had:
```typescript
export interface ViewOut {
  id: string;
  positions: { [key: string]: any; };
  whitelist: Array<string>;
  blacklist: Array<string>;
  createdAt: number | null;
  updatedAt: number | null;
}
```

3. Missing fields:
   - `include_recursive`
   - `exclude_recursive`
   - `hide_completed_for`

### Root Cause

The OpenAPI schema (`openapi.json`) used to generate the TypeScript client was out of date. It didn't include the new fields that were already in:
- Backend model definition (`backend/app/models.py`)
- Backend API routes (`backend/app/api/routes.py`)
- Running backend server responses

## Investigation Steps

1. **Checked backend models** - Found the fields were defined correctly:
   ```python
   class ViewOut(BaseModel):
       id: str
       positions: dict
       include_recursive: list[str]
       exclude_recursive: list[str]
       hide_completed_for: int | None = None
       created_at: int | None
       updated_at: int | None
   ```

2. **Checked API routes** - Confirmed the conversion was correct:
   ```python
   def _view_to_out(view: services.View) -> ViewOut:
       return ViewOut(
           id=view.id,
           positions=view.positions,
           include_recursive=view.include_recursive,
           exclude_recursive=view.exclude_recursive,
           hide_completed_for=view.hide_completed_for,
           created_at=view.created_at,
           updated_at=view.updated_at,
       )
   ```

3. **Checked OpenAPI spec** - Found it was missing the fields from the ViewOut schema definition

## Why It Happened

The `openapi.json` file was stale. When attempting to regenerate from the remote backend (`http://100.83.86.3/todo`), the `/openapi.json` endpoint wasn't properly exposed, resulting in HTML being returned instead of JSON. The local backend instance was also outdated.

## Resolution

1. **Manually updated `openapi.json`** to add the missing fields to the ViewOut schema using `jq`:
   ```bash
   jq '.components.schemas.ViewOut.properties += {
     "include_recursive": { ... },
     "exclude_recursive": { ... },
     "hide_completed_for": { ... }
   }'
   ```

2. **Regenerated the TypeScript client** using OpenAPI Generator with the corrected schema

3. **Built and committed** the updated client to GitHub:
   - Commit: `ac20600` - "Regenerate client with ViewOut schema updates"
   - This updated `backend/repo` (todo-client)

4. **Rebuilt the frontend** with the updated client package and pushed changes:
   - Commit: `724a154` - "Update frontend: rebuild with updated todo-client"
   - This updated `frontend/repo` (todo-gui)

5. **Updated main repo** submodule references:
   - Commit: `88b401a` - "Update submodules: ViewOut schema updates"

## Key Learnings

1. **OpenAPI schema must be kept in sync** - The source of truth should be the backend models, and the OpenAPI schema should be regenerated whenever models change

2. **Schema generation process vulnerability** - The `generate.sh` script fetches from a running backend, which can fail or be outdated. Consider:
   - Having a pre-committed, validated `openapi.json`
   - CI/CD validation that schema matches backend code
   - Regular regeneration from upstream

3. **Version mismatches** - When backend code and generated clients diverge, it creates silent data loss where fields are returned but ignored by the client

4. **Multiple backend instances** - Having different versions running (localhost:8000 vs 100.83.86.3) can cause confusion during troubleshooting

## Files Modified

- `backend/repo/client/openapi.json` - Updated ViewOut schema
- `backend/repo/client/generated/models/ViewOut.ts` - Regenerated with new fields
- `frontend/repo/dist/` - Rebuilt with updated client
- `frontend/repo/test-display-subscribe.js` - Created for testing the subscription

## Verification

The updated client now properly types view data:
```typescript
export interface ViewOut {
  id: string;
  positions: { [key: string]: any; };
  whitelist: Array<string>;
  blacklist: Array<string>;
  createdAt: number | null;
  updatedAt: number | null;
  includeRecursive: Array<string>;        // ✅ NEW
  excludeRecursive: Array<string>;         // ✅ NEW
  hideCompletedFor?: number | null;        // ✅ NEW
}
```
