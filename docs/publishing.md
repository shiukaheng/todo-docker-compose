# Client Publishing Instructions

## Status: Client Code Updated But Not Published

### ✅ What's Committed

**Main repo (todo-docker-compose):**
- ✅ Backend submodule updated with new schema
- ✅ Frontend submodule updated with rendering changes
- ✅ Documentation files added
- ✅ Database backup files included

**Backend submodule (backend/repo):**
- ✅ OpenAPI schema regenerated (`client/openapi.json`)
- ✅ TypeScript client generated (`client/generated/`)
- ✅ Routes updated (routes.py, sse.py)
- ✅ All committed in commit `c50227d`

**Frontend submodule (frontend/repo):**
- ✅ Shape rendering updated (3 new shapes)
- ✅ Backend calculations usage (removed redundant code)
- ✅ NodeDetailOverlay updated (dropdown + field names)
- ✅ All committed in commit `721e914`

### ⚠️ What's NOT Published

**The TypeScript Client Package:**

Frontend installs from: `github:shiukaheng/todo`
Generated client location: `backend/repo/client/`
Status: **Code is generated and committed, but NOT pushed to the separate "todo" repo**

This means:
- ✅ Current running frontend works (I manually copied generated client to node_modules)
- ❌ Fresh `npm install` would pull OLD client from github:shiukaheng/todo
- ❌ Other developers would get OLD types (inferred, calculatedCompleted)

## Required Actions

### Option 1: Publish to Separate "todo" Repo (Recommended)

The `backend/repo/client/` directory needs to be pushed to `github:shiukaheng/todo`:

```bash
# 1. Clone or navigate to the separate "todo" repo
git clone https://github.com/shiukaheng/todo.git /tmp/todo-client
cd /tmp/todo-client

# 2. Copy generated client from backend/repo/client
cp -r /mnt/workspace/repos/todo-docker-compose/backend/repo/client/* .

# 3. Commit and push
git add -A
git commit -m "Update to Boolean Graph schema: NodeType enum, calculated_value, is_actionable"
git push origin main

# 4. Update frontend to pull latest
cd /mnt/workspace/repos/todo-docker-compose/frontend/repo
npm update todo-client
```

### Option 2: Use Local Client (Alternative)

Change frontend to use local client instead of GitHub:

**In frontend/repo/package.json:**
```json
{
  "dependencies": {
    "todo-client": "file:../../backend/repo/client",
    ...
  }
}
```

Then reinstall:
```bash
cd /mnt/workspace/repos/todo-docker-compose/frontend/repo
npm install
```

**Pros:** No separate repo needed
**Cons:** Less portable, frontend depends on backend directory structure

### Option 3: Temporary Workaround (Current State)

For now, the system works because I manually copied the client:
```bash
cp -r backend/repo/client/generated frontend/repo/node_modules/todo-client/client/
```

**Pros:** Works immediately
**Cons:** Lost on `npm install`, not reproducible

## Verification After Publishing

After publishing the client to github:shiukaheng/todo:

```bash
# In a fresh clone/install
cd /mnt/workspace/repos/todo-docker-compose/frontend/repo
rm -rf node_modules
npm install

# Check if new types exist
grep "nodeType\|calculatedValue" node_modules/todo-client/client/generated/models/NodeOut.ts

# Should see:
# nodeType: NodeType;
# calculatedValue: boolean | null;
```

## Current Workaround Status

**For immediate use:**
- ✅ System is working (manual copy in node_modules)
- ✅ Backend committed and will auto-reload
- ✅ Frontend build includes new types

**For production/team use:**
- ⚠️ Must publish client to github:shiukaheng/todo
- ⚠️ OR switch to local file: dependency
- ⚠️ OR document the manual copy step

## Files Affected

**Backend (committed):**
- `client/openapi.json` - Updated schema
- `client/generated/models/NodeOut.ts` - New NodeOut type
- `client/generated/models/NodeType.ts` - NEW enum
- `client/generated/models/NodeCreate.ts` - Updated create type
- `client/generated/models/NodeUpdate.ts` - Updated update type
- All other generated files

**Frontend (committed):**
- `src/graph/preprocess/styleGraphData.ts` - Uses new fields
- `src/graph/render/utils.ts` - New shape types
- `src/graph/render/SVGRenderer.ts` - Shape implementations
- `src/graph/NodeDetailOverlay.tsx` - Dropdown + new fields

---

**Action Required:** Choose Option 1, 2, or 3 above to ensure reproducible client installation.

**Current Status:** Working locally but needs client publishing for team/production use.
