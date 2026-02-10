# Graph Backup - Pre-Boolean Logic Schema Migration

**Backup Date:** 2026-02-10 13:35:15
**Backup File:** `graph_backup_20260210_133515.json`

## Current Graph Statistics

- **Total Tasks:** 19
- **Inferred Tasks:** 2 (will become `:And` nodes)
- **Completed Tasks:** 1
- **Dependencies:** 17 DEPENDS_ON relationships

## Current Schema

```cypher
(:Task {
  id: string,
  text: string | null,
  completed: boolean,
  inferred: boolean,
  due: int | null,
  created_at: int,
  updated_at: int
})

(Task)-[:DEPENDS_ON {id: string}]->(Task)
```

## Backup Contents

The backup file contains:
1. **Nodes array:** All 19 task nodes with full properties
2. **Relationships array:** All 17 DEPENDS_ON relationships with IDs

## Inferred Tasks (to become :And nodes)

Based on the backup:
1. `all-mask-ok` (id: 6)
2. `depth-reinit-fix` (id: 7, has text property)

## Restore Instructions

To restore this backup:
1. Use `./restore_graph.sh graph_backup_20260210_133515.json`
2. Follow the prompts to clear existing data
3. You'll need to manually recreate nodes/relationships from the JSON (or use APOC)

## Next Steps

Now ready to implement the Boolean Logic Graph schema from `new_schema_proposal.md`:
- Add `:Node` label to all nodes
- Convert inferred tasks to `:And` nodes
- Rename `DEPENDS_ON` → `INPUT` relationships
- Remove `inferred` and `completed` properties from logic gates
