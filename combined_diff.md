# Combined Diff: Boolean Graph Implementation (2026-02-10)

This document contains all changes made today (2026-02-10) to implement the Boolean Graph system.

## Table of Contents
1. [Backend Changes](#backend-changes)
2. [Frontend Changes](#frontend-changes)

---

# Backend Changes

diff --git a/backend/app/api/routes.py b/backend/app/api/routes.py
index 9dfe18c..cbc0eec 100644
--- a/backend/app/api/routes.py
+++ b/backend/app/api/routes.py
@@ -23,19 +23,20 @@ from app.api.sse import publisher
 router = APIRouter()
 
 
-def _enriched_to_out(et: services.EnrichedTask) -> TaskOut:
-    """Convert EnrichedTask to Pydantic model."""
+def _enriched_to_out(et: services.EnrichedNode) -> TaskOut:
+    """Convert EnrichedNode to Pydantic model."""
     return TaskOut(
-        id=et.task.id,
-        text=et.task.text,
-        completed=et.task.completed,
-        inferred=et.task.inferred,
-        due=et.task.due,
-        created_at=et.task.created_at,
-        updated_at=et.task.updated_at,
-        calculated_completed=et.calculated_completed,
+        id=et.node.id,
+        text=et.node.text,
+        node_type=et.node.node_type,
+        completed=et.node.completed,
+        due=et.node.due,
+        created_at=et.node.created_at,
+        updated_at=et.node.updated_at,
+        calculated_value=et.calculated_value,
         calculated_due=et.calculated_due,
         deps_clear=et.deps_clear,
+        is_actionable=et.is_actionable,
     )
 
 
@@ -68,12 +69,12 @@ async def subscribe_tasks():
 async def list_tasks():
     """List all tasks with computed properties."""
     with get_session() as session:
-        tasks, dependencies, has_cycles = session.execute_read(services.list_tasks)
+        nodes, dependencies, has_cycles = session.execute_read(services.list_nodes)
 
-    # Build parent/child lookup: task_id -> list of dependency IDs
+    # Build parent/child lookup: node_id -> list of dependency IDs
     # Edge: from_id -[DEPENDS_ON]-> to_id means from_id depends on to_id
-    # parents = high-level goals that depend on this task (things this task blocks)
-    # children = sub-tasks this task depends on (things that block this task)
+    # parents = high-level goals that depend on this node (things this node blocks)
+    # children = sub-nodes this node depends on (things that block this node)
     parents_map: dict[str, list[str]] = {}   # to_id -> [dep.id, ...] (things that depend on to_id)
     children_map: dict[str, list[str]] = {}  # from_id -> [dep.id, ...] (things from_id depends on)
     for dep in dependencies:
@@ -82,21 +83,22 @@ async def list_tasks():
 
     return TaskListOut(
         tasks={
-            t.task.id: TaskOut(
-                id=t.task.id,
-                text=t.task.text,
-                completed=t.task.completed,
-                inferred=t.task.inferred,
-                due=t.task.due,
-                created_at=t.task.created_at,
-                updated_at=t.task.updated_at,
-                calculated_completed=t.calculated_completed,
+            t.node.id: TaskOut(
+                id=t.node.id,
+                text=t.node.text,
+                node_type=t.node.node_type,
+                completed=t.node.completed,
+                due=t.node.due,
+                created_at=t.node.created_at,
+                updated_at=t.node.updated_at,
+                calculated_value=t.calculated_value,
                 calculated_due=t.calculated_due,
                 deps_clear=t.deps_clear,
-                parents=parents_map.get(t.task.id, []),
-                children=children_map.get(t.task.id, []),
+                is_actionable=t.is_actionable,
+                parents=parents_map.get(t.node.id, []),
+                children=children_map.get(t.node.id, []),
             )
-            for t in tasks
+            for t in nodes
         },
         dependencies={d.id: _dep_to_out(d) for d in dependencies},
         has_cycles=has_cycles,
@@ -107,29 +109,30 @@ async def list_tasks():
 async def get_task(task_id: str):
     """Get a single task with computed properties."""
     with get_session() as session:
-        task = session.execute_read(
-            lambda tx: services.get_task(tx, task_id)
+        node = session.execute_read(
+            lambda tx: services.get_node(tx, task_id)
         )
-        if not task:
+        if not node:
             raise HTTPException(status_code=404, detail=f"Task '{task_id}' not found")
         # Get dependencies to build parents/children
         dependencies = session.execute_read(services.list_dependencies)
 
-    # Build parent/child lists for this task
+    # Build parent/child lists for this node
     parents = [d.id for d in dependencies if d.to_id == task_id]
     children = [d.id for d in dependencies if d.from_id == task_id]
 
     return TaskOut(
-        id=task.task.id,
-        text=task.task.text,
-        completed=task.task.completed,
-        inferred=task.task.inferred,
-        due=task.task.due,
-        created_at=task.task.created_at,
-        updated_at=task.task.updated_at,
-        calculated_completed=task.calculated_completed,
-        calculated_due=task.calculated_due,
-        deps_clear=task.deps_clear,
+        id=node.node.id,
+        text=node.node.text,
+        node_type=node.node.node_type,
+        completed=node.node.completed,
+        due=node.node.due,
+        created_at=node.node.created_at,
+        updated_at=node.node.updated_at,
+        calculated_value=node.calculated_value,
+        calculated_due=node.calculated_due,
+        deps_clear=node.deps_clear,
+        is_actionable=node.is_actionable,
         parents=parents,
         children=children,
     )
@@ -140,13 +143,13 @@ async def add_task(req: TaskCreate):
     """Create a new task."""
     try:
         with get_session() as session:
-            task = session.execute_write(
-                lambda tx: services.add_task(
+            node = session.execute_write(
+                lambda tx: services.add_node(
                     tx,
                     id=req.id,
+                    node_type=req.node_type.value if req.node_type else "Task",
                     text=req.text,
                     completed=req.completed,
-                    inferred=req.inferred,
                     due=req.due,
                     depends=req.depends,
                     blocks=req.blocks,
@@ -159,16 +162,17 @@ async def add_task(req: TaskCreate):
 
     await publisher.broadcast()
     return TaskOut(
-        id=task.id,
-        text=task.text,
-        completed=task.completed,
-        inferred=task.inferred,
-        due=task.due,
-        created_at=task.created_at,
-        updated_at=task.updated_at,
-        calculated_completed=None,
+        id=node.id,
+        text=node.text,
+        node_type=node.node_type,
+        completed=node.completed,
+        due=node.due,
+        created_at=node.created_at,
+        updated_at=node.updated_at,
+        calculated_value=None,
         calculated_due=None,
         deps_clear=None,
+        is_actionable=None,
         parents=[],   # caller should re-fetch if depends/blocks were provided
         children=[],
     )
@@ -177,14 +181,17 @@ async def add_task(req: TaskCreate):
 @router.patch("/tasks/{task_id}", response_model=OperationResult)
 async def set_task(task_id: str, req: TaskUpdate):
     """Update a task's properties."""
+    print(f"[set_task] task_id={task_id}, req.node_type={req.node_type}, type={type(req.node_type)}")
+    node_type_value = req.node_type.value if req.node_type else None
+    print(f"[set_task] node_type_value={node_type_value}")
     with get_session() as session:
         found = session.execute_write(
-            lambda tx: services.update_task(
+            lambda tx: services.update_node(
                 tx,
                 id=task_id,
+                node_type=node_type_value,
                 text=req.text,
                 completed=req.completed,
-                inferred=req.inferred,
                 due=req.due,
             )
         )
@@ -201,7 +208,7 @@ async def remove_task(task_id: str):
     """Delete a task and its edges."""
     with get_session() as session:
         found = session.execute_write(
-            lambda tx: services.remove_task(tx, task_id)
+            lambda tx: services.remove_node(tx, task_id)
         )
 
     if not found:
@@ -217,7 +224,7 @@ async def rename_task(task_id: str, req: RenameRequest):
     try:
         with get_session() as session:
             session.execute_write(
-                lambda tx: services.rename_task(tx, task_id, req.new_id)
+                lambda tx: services.rename_node(tx, task_id, req.new_id)
             )
     except ValueError as e:
         raise HTTPException(status_code=400, detail=str(e))
@@ -237,7 +244,7 @@ async def link_tasks(req: LinkRequest):
     try:
         with get_session() as session:
             dep_id = session.execute_write(
-                lambda tx: services.link_tasks(tx, req.from_id, req.to_id)
+                lambda tx: services.link_nodes(tx, req.from_id, req.to_id)
             )
     except ValueError as e:
         raise HTTPException(status_code=400, detail=str(e))
@@ -251,7 +258,7 @@ async def unlink_tasks(req: LinkRequest):
     """Remove a dependency."""
     with get_session() as session:
         found = session.execute_write(
-            lambda tx: services.unlink_tasks(tx, req.from_id, req.to_id)
+            lambda tx: services.unlink_nodes(tx, req.from_id, req.to_id)
         )
 
     if not found:
diff --git a/backend/app/api/sse.py b/backend/app/api/sse.py
index 9ff1160..1173406 100644
--- a/backend/app/api/sse.py
+++ b/backend/app/api/sse.py
@@ -52,14 +52,14 @@ class SSEPublisher:
                     pass  # Skip slow clients
 
     def _get_current_state(self) -> dict:
-        """Get current task list state matching TaskListOut schema."""
+        """Get current task list state matching NodeListOut schema."""
         with get_session() as session:
-            tasks, dependencies, has_cycles = session.execute_read(services.list_tasks)
+            nodes, dependencies, has_cycles = session.execute_read(services.list_nodes)
 
-        # Build parent/child lookup: task_id -> list of dependency IDs
+        # Build parent/child lookup: node_id -> list of dependency IDs
         # Edge: from_id -[DEPENDS_ON]-> to_id means from_id depends on to_id
-        # parents = high-level goals that depend on this task (things this task blocks)
-        # children = sub-tasks this task depends on (things that block this task)
+        # parents = high-level goals that depend on this node (things this node blocks)
+        # children = sub-nodes this node depends on (things that block this node)
         parents_map: dict[str, list[str]] = {}   # to_id -> [dep.id, ...] (things that depend on to_id)
         children_map: dict[str, list[str]] = {}  # from_id -> [dep.id, ...] (things from_id depends on)
         for dep in dependencies:
@@ -68,21 +68,22 @@ class SSEPublisher:
 
         return {
             "tasks": {
-                et.task.id: {
-                    "id": et.task.id,
-                    "text": et.task.text,
-                    "completed": et.task.completed,
-                    "inferred": et.task.inferred,
-                    "due": et.task.due,
-                    "created_at": et.task.created_at,
-                    "updated_at": et.task.updated_at,
-                    "calculated_completed": et.calculated_completed,
+                et.node.id: {
+                    "id": et.node.id,
+                    "text": et.node.text,
+                    "node_type": et.node.node_type,
+                    "completed": et.node.completed,
+                    "due": et.node.due,
+                    "created_at": et.node.created_at,
+                    "updated_at": et.node.updated_at,
+                    "calculated_value": et.calculated_value,
                     "calculated_due": et.calculated_due,
                     "deps_clear": et.deps_clear,
-                    "parents": parents_map.get(et.task.id, []),
-                    "children": children_map.get(et.task.id, []),
+                    "is_actionable": et.is_actionable,
+                    "parents": parents_map.get(et.node.id, []),
+                    "children": children_map.get(et.node.id, []),
                 }
-                for et in tasks
+                for et in nodes
             },
             "dependencies": {
                 dep.id: {
diff --git a/backend/app/core/services.py b/backend/app/core/services.py
index b6acb3d..323e563 100644
--- a/backend/app/core/services.py
+++ b/backend/app/core/services.py
@@ -1,32 +1,31 @@
-"""Pure functional service layer for task operations."""
+"""Pure functional service layer for node operations - UPDATED FOR BOOLEAN GRAPH."""
 from __future__ import annotations
 
 import time
 import uuid
-from dataclasses import dataclass, field
-
-
+from dataclasses import dataclass
 
 
 @dataclass
-class Task:
-    """Task data."""
+class Node:
+    """Node data (any type)."""
     id: str
+    node_type: str  # "Task", "And", "Or", "Not", "ExactlyOne" - DERIVED from labels
     text: str = ""
-    completed: bool = False
-    inferred: bool = False
+    completed: bool | None = None  # Only for Task nodes
     due: int | None = None
     created_at: int | None = None
     updated_at: int | None = None
 
 
 @dataclass
-class EnrichedTask:
-    """Task with calculated properties."""
-    task: Task
-    calculated_completed: bool | None = None
+class EnrichedNode:
+    """Node with calculated properties."""
+    node: Node
+    calculated_value: bool | None = None  # Renamed from calculated_completed
     calculated_due: int | None = None
     deps_clear: bool | None = None
+    is_actionable: bool | None = None
 
 
 @dataclass
@@ -37,46 +36,42 @@ class Dependency:
     to_id: str
 
 
-_ENRICHMENT = """
-    OPTIONAL MATCH (t)-[:DEPENDS_ON]->(anyDep:Task)
-    OPTIONAL MATCH (t)<-[:DEPENDS_ON*]-(downstream:Task)
-    WHERE downstream <> t
-    WITH t,
-         collect(DISTINCT anyDep) AS all_deps,
-         [x IN collect(DISTINCT downstream.due) WHERE x IS NOT NULL] +
-           (CASE WHEN t.due IS NULL THEN [] ELSE [t.due] END) AS dues
-    RETURN t,
-           (t.inferred OR t.completed) AND (size(all_deps) = 0 OR all(d IN all_deps WHERE d.completed = true))
-             AS calculated_completed,
-           CASE WHEN size(dues) = 0 THEN NULL
-                ELSE reduce(d = head(dues), x IN dues | CASE WHEN x < d THEN x ELSE d END)
-           END AS calculated_due,
-           size(all_deps) = 0 OR all(d IN all_deps WHERE d.completed = true)
-             AS deps_clear
-"""
-
-
-def _node_to_task(node) -> Task:
-    """Convert Neo4j node to Task."""
-    d = dict(node)
-    return Task(
-        id=d.get("id", ""),
-        text=d.get("text", ""),
-        completed=d.get("completed", False),
-        inferred=d.get("inferred", False),
-        due=d.get("due"),
-        created_at=d.get("created_at"),
-        updated_at=d.get("updated_at"),
+# ============================================================================
+# Helper functions
+# ============================================================================
+
+
+def _extract_node_type(labels: list[str]) -> str:
+    """Extract node type from labels list."""
+    for label in labels:
+        if label in ["Task", "And", "Or", "Not", "ExactlyOne"]:
+            return label
+    return "Task"  # Default fallback
+
+
+def _node_to_dict(record) -> Node:
+    """Convert Neo4j record to Node."""
+    node_data = dict(record["n"])
+    labels = record["labels"]
+
+    return Node(
+        id=node_data.get("id", ""),
+        node_type=_extract_node_type(labels),
+        text=node_data.get("text", ""),
+        completed=node_data.get("completed"),  # None for gates
+        due=node_data.get("due"),
+        created_at=node_data.get("created_at"),
+        updated_at=node_data.get("updated_at"),
     )
 
 
-def _record_to_enriched(record, skip_calculated: bool = False) -> EnrichedTask:
-    """Convert query record to EnrichedTask."""
-    return EnrichedTask(
-        task=_node_to_task(record["t"]),
-        calculated_completed=None if skip_calculated else record.get("calculated_completed"),
-        calculated_due=None if skip_calculated else record.get("calculated_due"),
-        deps_clear=None if skip_calculated else record.get("deps_clear"),
+def _record_to_enriched(record) -> EnrichedNode:
+    """Convert query record to EnrichedNode (values calculated separately in Python)."""
+    return EnrichedNode(
+        node=_node_to_dict(record),
+        calculated_value=None,  # Calculated in Python later
+        calculated_due=None,     # Calculated in Python later
+        deps_clear=None,         # Calculated in Python later
     )
 
 
@@ -84,11 +79,92 @@ def _sort_by_updated(records: list) -> list:
     """Sort records by updated_at desc, falling back to created_at."""
     return sorted(
         records,
-        key=lambda r: dict(r["t"]).get("updated_at") or dict(r["t"]).get("created_at") or 0,
+        key=lambda r: dict(r["n"]).get("updated_at") or dict(r["n"]).get("created_at") or 0,
         reverse=True,
     )
 
 
+# ============================================================================
+# Pure calculation utilities (stateless, compositional)
+# ============================================================================
+
+def _calculate_gate_logic(node_type: str, dep_values: list[bool]) -> bool:
+    """Calculate gate-specific logic on dependencies (used for both calculated_value and deps_clear).
+
+    For Task and And: AND logic (all deps must be true)
+    For Or: OR logic (any dep must be true)
+    For Not: NOR logic (no deps must be true)
+    For ExactlyOne: XOR logic (exactly one dep must be true)
+    """
+    match node_type:
+        case "Task" | "And": return not dep_values or all(dep_values)
+        case "Or": return bool(dep_values) and any(dep_values)
+        case "Not": return not any(dep_values)
+        case "ExactlyOne": return sum(dep_values) == 1
+        case _: return True
+
+
+def _memoized(fn):
+    """Memoization decorator for single-arg functions."""
+    cache = {}
+    def wrapper(arg):
+        if arg not in cache:
+            cache[arg] = fn(arg)
+        return cache[arg]
+    return wrapper
+
+
+def _build_value_calculator(nodes: dict[str, Node], deps: dict[str, list[str]]):
+    """Build a memoized value calculator closure.
+
+    calculated_value = own_value AND deps_clear
+    - Task: own_value = completed, deps_clear = all(deps.calculated_value)
+    - Gates: own_value = true (identity), deps_clear = gate_logic(deps.calculated_value)
+    """
+    @_memoized
+    def calculate(node_id: str) -> bool:
+        node = nodes[node_id]
+        dep_values = [calculate(dep_id) for dep_id in deps.get(node_id, [])]
+
+        # deps_clear is gate-specific evaluation of dependencies
+        deps_clear = _calculate_gate_logic(node.node_type, dep_values)
+
+        if node.node_type == "Task":
+            # Task: calculated_value = completed AND deps_clear
+            return (node.completed or False) and deps_clear
+        else:
+            # Gates: calculated_value = deps_clear (no own value)
+            return deps_clear
+    return calculate
+
+
+def _build_due_calculator(nodes: dict[str, Node], downstream: dict[str, list[str]]):
+    """Build a memoized due date calculator closure."""
+    @_memoized
+    def calculate(node_id: str) -> int | None:
+        dues = [nodes[node_id].due] if nodes[node_id].due else []
+        dues.extend(filter(None, [calculate(d) for d in downstream.get(node_id, [])]))
+        return min(dues) if dues else None
+    return calculate
+
+
+def _build_graph_indexes(nodes: list[Node], deps: list[Dependency]):
+    """Build lookup indexes from raw data."""
+    nodes_by_id = {n.id: n for n in nodes}
+
+    deps_fwd = {}  # from_id -> [to_id, ...]
+    deps_rev = {}  # to_id -> [from_id, ...]
+    for d in deps:
+        deps_fwd.setdefault(d.from_id, []).append(d.to_id)
+        deps_rev.setdefault(d.to_id, []).append(d.from_id)
+
+    return nodes_by_id, deps_fwd, deps_rev
+
+
+# Simplified Cypher query - just fetch data
+_ENRICHMENT = """ RETURN n, labels(n) AS labels """
+
+
 # ============================================================================
 # Read operations
 # ============================================================================
@@ -97,60 +173,15 @@ def _sort_by_updated(records: list) -> list:
 def has_cycles(tx) -> bool:
     """Check if the graph has any cycles."""
     result = tx.run(
-        "MATCH (t:Task) WHERE (t)-[:DEPENDS_ON*1..]->(t) RETURN t.id LIMIT 1"
+        "MATCH (n:Node) WHERE (n)-[:DEPENDS_ON*1..]->(n) RETURN n.id LIMIT 1"
     )
     return result.single() is not None
 
 
-# Reusable finalization suffix. Expects `_passthrough` variable to exist.
-# Returns: _passthrough (preserved), _reduced (count), _errors (list)
-_FINALIZE_SUFFIX = """
-// Transitive reduction: remove edges implied by longer paths
-CALL {
-    MATCH (a:Task)-[direct:DEPENDS_ON]->(c:Task)
-    WHERE EXISTS { MATCH (a)-[:DEPENDS_ON*2..]->(c) }
-    DELETE direct
-    RETURN count(direct) AS cnt
-}
-WITH _passthrough, cnt AS _reduced
-
-// Collect validation errors
-CALL {
-    OPTIONAL MATCH (t:Task) WHERE (t)-[:DEPENDS_ON*1..]->(t)
-    WITH t LIMIT 1
-    RETURN CASE WHEN t IS NOT NULL THEN 'Cycle involving: ' + t.id ELSE NULL END AS err
-    UNION ALL
-    OPTIONAL MATCH (t:Task)-[:DEPENDS_ON]->(t)
-    WITH t LIMIT 1
-    RETURN CASE WHEN t IS NOT NULL THEN 'Self-loop: ' + t.id ELSE NULL END AS err
-    UNION ALL
-    OPTIONAL MATCH (a:Task)-[r:DEPENDS_ON]->(b:Task)
-    WITH a.id AS from_id, b.id AS to_id, count(r) AS cnt
-    WHERE cnt > 1
-    WITH from_id, to_id, cnt LIMIT 1
-    RETURN CASE WHEN cnt > 1 THEN 'Duplicate edges: ' + from_id + ' -> ' + to_id ELSE NULL END AS err
-    UNION ALL
-    OPTIONAL MATCH (a:Task)-[r:DEPENDS_ON]->(b:Task)
-    WHERE r.id IS NULL
-    WITH a, b LIMIT 1
-    RETURN CASE WHEN a IS NOT NULL THEN 'Missing ID: ' + a.id + ' -> ' + b.id ELSE NULL END AS err
-}
-WITH _passthrough, _reduced, collect(err) AS _errs
-WITH _passthrough, _reduced, [e IN _errs WHERE e IS NOT NULL] AS _errors
-"""
-
-
-def _check_finalize_errors(record) -> None:
-    """Check finalize result for errors and raise if any."""
-    errors = record["_errors"]
-    if errors:
-        raise ValueError("; ".join(errors))
-
-
 def list_dependencies(tx) -> list[Dependency]:
     """List all dependencies."""
     result = tx.run(
-        "MATCH (a:Task)-[r:DEPENDS_ON]->(b:Task) "
+        "MATCH (a:Node)-[r:DEPENDS_ON]->(b:Node) "
         "RETURN r.id AS id, a.id AS from_id, b.id AS to_id"
     )
     return [
@@ -163,29 +194,57 @@ def list_dependencies(tx) -> list[Dependency]:
     ]
 
 
-def get_task(tx, id: str) -> EnrichedTask | None:
-    """Get a single task with computed properties."""
-    result = tx.run(
-        "MATCH (t:Task {id: $id})" + _ENRICHMENT,
-        id=id
-    )
-    record = result.single()
+def get_node(tx, id: str) -> EnrichedNode | None:
+    """Get a single node with computed properties."""
+    record = tx.run("MATCH (n:Node {id: $id})" + _ENRICHMENT, id=id).single()
     if not record:
         return None
-    return _record_to_enriched(record)
 
+    enriched = _record_to_enriched(record)
 
-def list_tasks(tx) -> tuple[list[EnrichedTask], list[Dependency], bool]:
-    """List all tasks with computed properties.
+    if not has_cycles(tx):
+        # Reuse list_nodes logic for consistency
+        all_nodes = [_node_to_dict(r) for r in tx.run("MATCH (n:Node)" + _ENRICHMENT)]
+        dependencies = list_dependencies(tx)
 
-    Returns (tasks, dependencies, has_cycles).
-    """
-    graph_has_cycles = has_cycles(tx)
-    result = tx.run("MATCH (t:Task)" + _ENRICHMENT)
-    records = _sort_by_updated(list(result))
-    tasks = [_record_to_enriched(r, skip_calculated=graph_has_cycles) for r in records]
+        nodes_map, deps_fwd, deps_rev = _build_graph_indexes(all_nodes, dependencies)
+        calc_value = _build_value_calculator(nodes_map, deps_fwd)
+        calc_due = _build_due_calculator(nodes_map, deps_rev)
+
+        enriched.calculated_value = calc_value(id)
+        enriched.calculated_due = calc_due(id)
+        # deps_clear = gate-specific evaluation of dependencies
+        dep_values = [calc_value(d) for d in deps_fwd.get(id, [])]
+        enriched.deps_clear = _calculate_gate_logic(enriched.node.node_type, dep_values)
+        enriched.is_actionable = enriched.node.node_type == "Task" and not (enriched.node.completed or False) and enriched.deps_clear
+
+    return enriched
+
+
+def list_nodes(tx) -> tuple[list[EnrichedNode], list[Dependency], bool]:
+    """List all nodes with computed properties."""
+    # Fetch data
+    records = _sort_by_updated(list(tx.run("MATCH (n:Node)" + _ENRICHMENT)))
+    enriched = [_record_to_enriched(r) for r in records]
     dependencies = list_dependencies(tx)
-    return tasks, dependencies, graph_has_cycles
+    graph_has_cycles = has_cycles(tx)
+
+    if not graph_has_cycles:
+        # Build indexes and calculators
+        nodes_map, deps_fwd, deps_rev = _build_graph_indexes([e.node for e in enriched], dependencies)
+        calc_value = _build_value_calculator(nodes_map, deps_fwd)
+        calc_due = _build_due_calculator(nodes_map, deps_rev)
+
+        # Calculate properties
+        for e in enriched:
+            e.calculated_value = calc_value(e.node.id)
+            e.calculated_due = calc_due(e.node.id)
+            # deps_clear = gate-specific evaluation of dependencies
+            dep_values = [calc_value(d) for d in deps_fwd.get(e.node.id, [])]
+            e.deps_clear = _calculate_gate_logic(e.node.node_type, dep_values)
+            e.is_actionable = e.node.node_type == "Task" and not (e.node.completed or False) and e.deps_clear
+
+    return enriched, dependencies, graph_has_cycles
 
 
 # ============================================================================
@@ -193,22 +252,20 @@ def list_tasks(tx) -> tuple[list[EnrichedTask], list[Dependency], bool]:
 # ============================================================================
 
 
-def add_task(
+def add_node(
     tx,
     id: str,
+    node_type: str = "Task",
     text: str | None = None,
     completed: bool = False,
-    inferred: bool = False,
-    due: str | None = None,
+    due: int | None = None,
     depends: list[str] | None = None,
     blocks: list[str] | None = None,
-) -> Task:
-    """Create a new task."""
+) -> Node:
+    """Create a new node of any type."""
     now = int(time.time())
     props = {
         "id": id,
-        "completed": completed,
-        "inferred": inferred,
         "created_at": now,
         "updated_at": now,
     }
@@ -217,101 +274,143 @@ def add_task(
     if due is not None:
         props["due"] = due
 
-    tx.run("CREATE (t:Task $props)", props=props)
+    # Only add completed for Task nodes
+    if node_type == "Task":
+        props["completed"] = completed
+
+    # Create with appropriate labels
+    labels = f":Node:{node_type}"
+    tx.run(f"CREATE (n{labels} $props)", props=props)
 
+    # Create DEPENDS_ON relationships
     for dep_id in (depends or []):
         _create_dependency(tx, id, dep_id)
     for block_id in (blocks or []):
         _create_dependency(tx, block_id, id)
 
-    return Task(**{k: v for k, v in props.items() if k in Task.__dataclass_fields__})
+    return Node(
+        id=id,
+        node_type=node_type,
+        text=props.get("text", ""),
+        completed=props.get("completed"),
+        due=props.get("due"),
+        created_at=now,
+        updated_at=now,
+    )
 
 
-def update_task(
+def update_node(
     tx,
     id: str,
+    node_type: str | None = None,
     text: str | None = None,
     completed: bool | None = None,
-    inferred: bool | None = None,
-    due: str | None = None,
+    due: int | None = None,
 ) -> bool:
-    """Update an existing task. Returns True if found."""
+    """Update an existing node. Returns True if found."""
+    now = int(time.time())
+
+    # If changing type, handle label changes
+    if node_type is not None:
+        # Get current labels
+        result = tx.run(
+            "MATCH (n:Node {id: $id}) RETURN labels(n) AS labels",
+            id=id
+        )
+        record = result.single()
+        if not record:
+            return False
+
+        current_labels = record["labels"]
+        current_type = _extract_node_type(current_labels)
+
+        if current_type != node_type:
+            # Change node type
+            query = (
+                f"MATCH (n:{current_type} {{id: $id}}) "
+                f"REMOVE n:{current_type} "
+                f"SET n:{node_type}, n.updated_at = $now "
+                # Add completed if converting TO Task
+                + (f"SET n.completed = {str(completed if completed is not None else False).lower()} "
+                   if node_type == "Task" and current_type != "Task" else "")
+                # Remove completed if converting FROM Task
+                + ("REMOVE n.completed " if current_type == "Task" and node_type != "Task" else "")
+            )
+            print(f"[update_node] Changing type: {current_type} -> {node_type}, query: {query}")
+            result = tx.run(query, id=id, now=now)
+            print(f"[update_node] Result: {result.consume().counters}")
+
+    # Update other properties
     props = {}
     if text is not None:
         props["text"] = text
     if completed is not None:
         props["completed"] = completed
-    if inferred is not None:
-        props["inferred"] = inferred
     if due is not None:
         props["due"] = due
 
-    if not props:
-        # Check if task exists
-        result = tx.run("MATCH (t:Task {id: $id}) RETURN t", id=id)
+    if props:
+        props["updated_at"] = now
+        result = tx.run(
+            "MATCH (n:Node {id: $id}) SET n += $props RETURN n",
+            id=id, props=props
+        )
         return result.single() is not None
 
-    props["updated_at"] = int(time.time())
-    result = tx.run(
-        "MATCH (t:Task {id: $id}) SET t += $props RETURN t",
-        id=id, props=props
-    )
-    return result.single() is not None
+    return True
 
 
-def link_tasks(tx, from_id: str, to_id: str) -> str:
+def link_nodes(tx, from_id: str, to_id: str) -> str:
     """Create dependency: from_id depends on to_id. Returns the dependency ID."""
     return _create_dependency(tx, from_id, to_id)
 
 
-def unlink_tasks(tx, from_id: str, to_id: str) -> bool:
+def unlink_nodes(tx, from_id: str, to_id: str) -> bool:
     """Remove dependency. Returns True if found."""
     result = tx.run(
-        "MATCH (a:Task {id: $from_id})-[r:DEPENDS_ON]->(b:Task {id: $to_id}) "
+        "MATCH (a:Node {id: $from_id})-[r:DEPENDS_ON]->(b:Node {id: $to_id}) "
         "DELETE r RETURN count(r) AS n",
         from_id=from_id, to_id=to_id
     )
     return result.single()["n"] > 0
 
 
-def remove_task(tx, id: str) -> bool:
-    """Remove a task. Returns True if found."""
+def remove_node(tx, id: str) -> bool:
+    """Remove a node. Returns True if found."""
     result = tx.run(
-        "MATCH (t:Task {id: $id}) DETACH DELETE t RETURN count(t) AS n",
+        "MATCH (n:Node {id: $id}) DETACH DELETE n RETURN count(n) AS n",
         id=id
     )
     return result.single()["n"] > 0
 
 
-def rename_task(tx, old_id: str, new_id: str) -> None:
-    """Rename a task. Raises if old not found or new already exists."""
+def rename_node(tx, old_id: str, new_id: str) -> None:
+    """Rename a node. Raises if old not found or new already exists."""
     if old_id == new_id:
         raise ValueError("Old and new IDs are the same")
 
     # Check new ID doesn't exist
-    if tx.run("MATCH (t:Task {id: $id}) RETURN t", id=new_id).single():
-        raise ValueError(f"Task '{new_id}' already exists")
+    if tx.run("MATCH (n:Node {id: $id}) RETURN n", id=new_id).single():
+        raise ValueError(f"Node '{new_id}' already exists")
 
     result = tx.run(
-        "MATCH (t:Task {id: $old_id}) SET t.id = $new_id, t.updated_at = $now RETURN t",
+        "MATCH (n:Node {id: $old_id}) SET n.id = $new_id, n.updated_at = $now RETURN n",
         old_id=old_id, new_id=new_id, now=int(time.time())
     )
     if not result.single():
-        raise ValueError(f"Task '{old_id}' not found")
+        raise ValueError(f"Node '{old_id}' not found")
 
 
 _CREATE_DEPENDENCY_QUERY = (
-    "MATCH (a:Task {id: $from_id}), (b:Task {id: $to_id}) "
+    "MATCH (a:Node {id: $from_id}), (b:Node {id: $to_id}) "
     "MERGE (a)-[r:DEPENDS_ON]->(b) "
     "ON CREATE SET r.id = $dep_id "
-    "WITH {dep_id: r.id, found: true} AS _passthrough "
-    + _FINALIZE_SUFFIX +
-    "RETURN _passthrough.dep_id AS dep_id, _passthrough.found AS found, _reduced, _errors"
+    "RETURN r.id AS dep_id, true AS found"
 )
 
 
 def _create_dependency(tx, from_id: str, to_id: str) -> str:
-    """Create a dependency edge with finalization. Returns the dependency ID."""
+    """Create a dependency edge. Returns the dependency ID."""
     if from_id == to_id:
         raise ValueError(f"Self-loop not allowed: {from_id}")
 
@@ -322,8 +421,7 @@ def _create_dependency(tx, from_id: str, to_id: str) -> str:
     )
     record = result.single()
     if not record or not record["found"]:
-        raise ValueError(f"Task not found: {from_id} or {to_id}")
-    _check_finalize_errors(record)
+        raise ValueError(f"Node not found: {from_id} or {to_id}")
     return record["dep_id"]
 
 
@@ -334,16 +432,39 @@ def _create_dependency(tx, from_id: str, to_id: str) -> str:
 
 def init_db(tx) -> None:
     """Initialize database constraints."""
+    # Drop old constraint
+    tx.run("DROP CONSTRAINT task_id_unique IF EXISTS")
+
+    # Create new constraint
+    tx.run(
+        "CREATE CONSTRAINT node_id_unique IF NOT EXISTS "
+        "FOR (n:Node) REQUIRE n.id IS UNIQUE"
+    )
+
+
+def migrate_to_boolean_graph(tx) -> None:
+    """Migrate existing Task nodes to boolean graph schema."""
+    # 1. Add :Node label to all tasks
+    tx.run("MATCH (t:Task) SET t:Node")
+
+    # 2. Convert inferred tasks to And gates
+    tx.run(
+        "MATCH (t:Task {inferred: true}) "
+        "SET t:And "
+        "REMOVE t:Task, t.completed, t.inferred"
+    )
+
+    # 3. Remove inferred from regular tasks
     tx.run(
-        "CREATE CONSTRAINT task_id_unique IF NOT EXISTS "
-        "FOR (t:Task) REQUIRE t.id IS UNIQUE"
+        "MATCH (t:Task {inferred: false}) "
+        "REMOVE t.inferred"
     )
 
 
 def migrate_dependency_ids(tx) -> None:
     """Assign UUIDs to any relationships missing an ID."""
     tx.run(
-        "MATCH (a:Task)-[r:DEPENDS_ON]->(b:Task) "
+        "MATCH (a:Node)-[r:DEPENDS_ON]->(b:Node) "
         "WHERE r.id IS NULL "
         "SET r.id = randomUUID()"
     )
@@ -352,7 +473,21 @@ def migrate_dependency_ids(tx) -> None:
 def prime_tokens(tx) -> None:
     """Create and delete a dummy node to register property keys."""
     tx.run(
-        "CREATE (t:__InitTokenRegistration:Task {id: '__init__', due: 0, completed: false, inferred: false, created_at: 0, updated_at: 0, text: ''}) "
-        "CREATE (t)-[:DEPENDS_ON {id: '__init__'}]->(t) "
-        "DETACH DELETE t"
+        "CREATE (n:__InitTokenRegistration:Node:Task "
+        "{id: '__init__', due: 0, completed: false, created_at: 0, updated_at: 0, text: ''}) "
+        "CREATE (n)-[:DEPENDS_ON {id: '__init__'}]->(n) "
+        "DETACH DELETE n"
     )
+
+
+# Backward compatibility aliases
+Task = Node
+EnrichedTask = EnrichedNode
+add_task = add_node
+update_task = update_node
+get_task = get_node
+list_tasks = list_nodes
+rename_task = rename_node
+remove_task = remove_node
+link_tasks = link_nodes
+unlink_tasks = unlink_nodes
diff --git a/backend/app/models.py b/backend/app/models.py
index 7a1601a..f95389b 100644
--- a/backend/app/models.py
+++ b/backend/app/models.py
@@ -1,46 +1,58 @@
-"""Pydantic models for API."""
+"""Pydantic models for API - UPDATED FOR BOOLEAN GRAPH."""
 from __future__ import annotations
 
+from enum import Enum
 from pydantic import BaseModel
 
 
-class TaskBase(BaseModel):
-    """Base task properties."""
+# NEW: Node type enum
+class NodeType(str, Enum):
+    """Node type labels."""
+    TASK = "Task"
+    AND = "And"
+    OR = "Or"
+    NOT = "Not"
+    EXACTLY_ONE = "ExactlyOne"
+
+
+class NodeBase(BaseModel):
+    """Base node properties."""
     text: str | None = None
-    completed: bool = False
-    inferred: bool = False
+    completed: bool = False  # Only used for Task nodes (ignored for gates)
+    node_type: NodeType = NodeType.TASK  # NEW: replaces 'inferred'
     due: int | None = None
 
 
-class TaskCreate(TaskBase):
-    """Task creation request."""
+class NodeCreate(NodeBase):
+    """Node creation request."""
     id: str
-    depends: list[str] | None = None
+    depends: list[str] | None = None  # Still using depends/blocks (DEPENDS_ON relationship)
     blocks: list[str] | None = None
 
 
-class TaskUpdate(BaseModel):
-    """Task update request."""
+class NodeUpdate(BaseModel):
+    """Node update request."""
     text: str | None = None
     completed: bool | None = None
-    inferred: bool | None = None
+    node_type: NodeType | None = None  # NEW: can change node type
     due: int | None = None
 
 
-class TaskOut(BaseModel):
-    """Task response with calculated fields."""
+class NodeOut(BaseModel):
+    """Node response with calculated fields."""
     id: str
     text: str
-    completed: bool
-    inferred: bool
+    node_type: NodeType  # NEW: derived from labels
+    completed: bool | None  # None for gate nodes
     due: int | None
     created_at: int | None
     updated_at: int | None
-    calculated_completed: bool | None
+    calculated_value: bool | None  # NEW: renamed from calculated_completed
     calculated_due: int | None
     deps_clear: bool | None
-    parents: list[str]    # dependency IDs where this task is to_id (high-level goals depending on this)
-    children: list[str]   # dependency IDs where this task is from_id (sub-tasks this depends on)
+    is_actionable: bool | None  # NEW: only true for Tasks that are incomplete and unblocked
+    parents: list[str]    # dependency IDs where this node is to_id
+    children: list[str]   # dependency IDs where this node is from_id
 
 
 class DependencyOut(BaseModel):
@@ -50,9 +62,9 @@ class DependencyOut(BaseModel):
     to_id: str
 
 
-class TaskListOut(BaseModel):
-    """Task list response."""
-    tasks: dict[str, TaskOut]
+class NodeListOut(BaseModel):
+    """Node list response."""
+    tasks: dict[str, NodeOut]  # Keep name 'tasks' for backward compatibility
     dependencies: dict[str, DependencyOut]
     has_cycles: bool
 
@@ -72,3 +84,10 @@ class OperationResult(BaseModel):
     """Generic operation result."""
     success: bool
     message: str | None = None
+
+
+# Backward compatibility aliases (optional)
+TaskCreate = NodeCreate
+TaskUpdate = NodeUpdate
+TaskOut = NodeOut
+TaskListOut = NodeListOut
diff --git a/client/generated/.openapi-generator/FILES b/client/generated/.openapi-generator/FILES
index ece1607..868d417 100644
--- a/client/generated/.openapi-generator/FILES
+++ b/client/generated/.openapi-generator/FILES
@@ -5,24 +5,26 @@ docs/DependencyOut.md
 docs/HTTPValidationError.md
 docs/LinkRequest.md
 docs/LocationInner.md
+docs/NodeCreate.md
+docs/NodeListOut.md
+docs/NodeOut.md
+docs/NodeType.md
+docs/NodeUpdate.md
 docs/OperationResult.md
 docs/RenameRequest.md
-docs/TaskCreate.md
-docs/TaskListOut.md
-docs/TaskOut.md
-docs/TaskUpdate.md
 docs/ValidationError.md
 index.ts
 models/DependencyOut.ts
 models/HTTPValidationError.ts
 models/LinkRequest.ts
 models/LocationInner.ts
+models/NodeCreate.ts
+models/NodeListOut.ts
+models/NodeOut.ts
+models/NodeType.ts
+models/NodeUpdate.ts
 models/OperationResult.ts
 models/RenameRequest.ts
-models/TaskCreate.ts
-models/TaskListOut.ts
-models/TaskOut.ts
-models/TaskUpdate.ts
 models/ValidationError.ts
 models/index.ts
 runtime.ts
diff --git a/client/generated/apis/DefaultApi.ts b/client/generated/apis/DefaultApi.ts
index 1349813..7e821b1 100644
--- a/client/generated/apis/DefaultApi.ts
+++ b/client/generated/apis/DefaultApi.ts
@@ -18,12 +18,12 @@ import type {
   DependencyOut,
   HTTPValidationError,
   LinkRequest,
+  NodeCreate,
+  NodeListOut,
+  NodeOut,
+  NodeUpdate,
   OperationResult,
   RenameRequest,
-  TaskCreate,
-  TaskListOut,
-  TaskOut,
-  TaskUpdate,
 } from '../models/index';
 import {
     DependencyOutFromJSON,
@@ -32,22 +32,22 @@ import {
     HTTPValidationErrorToJSON,
     LinkRequestFromJSON,
     LinkRequestToJSON,
+    NodeCreateFromJSON,
+    NodeCreateToJSON,
+    NodeListOutFromJSON,
+    NodeListOutToJSON,
+    NodeOutFromJSON,
+    NodeOutToJSON,
+    NodeUpdateFromJSON,
+    NodeUpdateToJSON,
     OperationResultFromJSON,
     OperationResultToJSON,
     RenameRequestFromJSON,
     RenameRequestToJSON,
-    TaskCreateFromJSON,
-    TaskCreateToJSON,
-    TaskListOutFromJSON,
-    TaskListOutToJSON,
-    TaskOutFromJSON,
-    TaskOutToJSON,
-    TaskUpdateFromJSON,
-    TaskUpdateToJSON,
 } from '../models/index';
 
 export interface AddTaskApiTasksPostRequest {
-    taskCreate: TaskCreate;
+    nodeCreate: NodeCreate;
 }
 
 export interface GetTaskApiTasksTaskIdGetRequest {
@@ -69,7 +69,7 @@ export interface RenameTaskApiTasksTaskIdRenamePostRequest {
 
 export interface SetTaskApiTasksTaskIdPatchRequest {
     taskId: string;
-    taskUpdate: TaskUpdate;
+    nodeUpdate: NodeUpdate;
 }
 
 export interface UnlinkTasksApiLinksDeleteRequest {
@@ -85,11 +85,11 @@ export class DefaultApi extends runtime.BaseAPI {
      * Create a new task.
      * Add Task
      */
-    async addTaskApiTasksPostRaw(requestParameters: AddTaskApiTasksPostRequest, initOverrides?: RequestInit | runtime.InitOverrideFunction): Promise<runtime.ApiResponse<TaskOut>> {
-        if (requestParameters['taskCreate'] == null) {
+    async addTaskApiTasksPostRaw(requestParameters: AddTaskApiTasksPostRequest, initOverrides?: RequestInit | runtime.InitOverrideFunction): Promise<runtime.ApiResponse<NodeOut>> {
+        if (requestParameters['nodeCreate'] == null) {
             throw new runtime.RequiredError(
-                'taskCreate',
-                'Required parameter "taskCreate" was null or undefined when calling addTaskApiTasksPost().'
+                'nodeCreate',
+                'Required parameter "nodeCreate" was null or undefined when calling addTaskApiTasksPost().'
             );
         }
 
@@ -107,17 +107,17 @@ export class DefaultApi extends runtime.BaseAPI {
             method: 'POST',
             headers: headerParameters,
             query: queryParameters,
-            body: TaskCreateToJSON(requestParameters['taskCreate']),
+            body: NodeCreateToJSON(requestParameters['nodeCreate']),
         }, initOverrides);
 
-        return new runtime.JSONApiResponse(response, (jsonValue) => TaskOutFromJSON(jsonValue));
+        return new runtime.JSONApiResponse(response, (jsonValue) => NodeOutFromJSON(jsonValue));
     }
 
     /**
      * Create a new task.
      * Add Task
      */
-    async addTaskApiTasksPost(requestParameters: AddTaskApiTasksPostRequest, initOverrides?: RequestInit | runtime.InitOverrideFunction): Promise<TaskOut> {
+    async addTaskApiTasksPost(requestParameters: AddTaskApiTasksPostRequest, initOverrides?: RequestInit | runtime.InitOverrideFunction): Promise<NodeOut> {
         const response = await this.addTaskApiTasksPostRaw(requestParameters, initOverrides);
         return await response.value();
     }
@@ -126,7 +126,7 @@ export class DefaultApi extends runtime.BaseAPI {
      * Get a single task with computed properties.
      * Get Task
      */
-    async getTaskApiTasksTaskIdGetRaw(requestParameters: GetTaskApiTasksTaskIdGetRequest, initOverrides?: RequestInit | runtime.InitOverrideFunction): Promise<runtime.ApiResponse<TaskOut>> {
+    async getTaskApiTasksTaskIdGetRaw(requestParameters: GetTaskApiTasksTaskIdGetRequest, initOverrides?: RequestInit | runtime.InitOverrideFunction): Promise<runtime.ApiResponse<NodeOut>> {
         if (requestParameters['taskId'] == null) {
             throw new runtime.RequiredError(
                 'taskId',
@@ -149,14 +149,14 @@ export class DefaultApi extends runtime.BaseAPI {
             query: queryParameters,
         }, initOverrides);
 
-        return new runtime.JSONApiResponse(response, (jsonValue) => TaskOutFromJSON(jsonValue));
+        return new runtime.JSONApiResponse(response, (jsonValue) => NodeOutFromJSON(jsonValue));
     }
 
     /**
      * Get a single task with computed properties.
      * Get Task
      */
-    async getTaskApiTasksTaskIdGet(requestParameters: GetTaskApiTasksTaskIdGetRequest, initOverrides?: RequestInit | runtime.InitOverrideFunction): Promise<TaskOut> {
+    async getTaskApiTasksTaskIdGet(requestParameters: GetTaskApiTasksTaskIdGetRequest, initOverrides?: RequestInit | runtime.InitOverrideFunction): Promise<NodeOut> {
         const response = await this.getTaskApiTasksTaskIdGetRaw(requestParameters, initOverrides);
         return await response.value();
     }
@@ -272,7 +272,7 @@ export class DefaultApi extends runtime.BaseAPI {
      * List all tasks with computed properties.
      * List Tasks
      */
-    async listTasksApiTasksGetRaw(initOverrides?: RequestInit | runtime.InitOverrideFunction): Promise<runtime.ApiResponse<TaskListOut>> {
+    async listTasksApiTasksGetRaw(initOverrides?: RequestInit | runtime.InitOverrideFunction): Promise<runtime.ApiResponse<NodeListOut>> {
         const queryParameters: any = {};
 
         const headerParameters: runtime.HTTPHeaders = {};
@@ -287,14 +287,14 @@ export class DefaultApi extends runtime.BaseAPI {
             query: queryParameters,
         }, initOverrides);
 
-        return new runtime.JSONApiResponse(response, (jsonValue) => TaskListOutFromJSON(jsonValue));
+        return new runtime.JSONApiResponse(response, (jsonValue) => NodeListOutFromJSON(jsonValue));
     }
 
     /**
      * List all tasks with computed properties.
      * List Tasks
      */
-    async listTasksApiTasksGet(initOverrides?: RequestInit | runtime.InitOverrideFunction): Promise<TaskListOut> {
+    async listTasksApiTasksGet(initOverrides?: RequestInit | runtime.InitOverrideFunction): Promise<NodeListOut> {
         const response = await this.listTasksApiTasksGetRaw(initOverrides);
         return await response.value();
     }
@@ -399,10 +399,10 @@ export class DefaultApi extends runtime.BaseAPI {
             );
         }
 
-        if (requestParameters['taskUpdate'] == null) {
+        if (requestParameters['nodeUpdate'] == null) {
             throw new runtime.RequiredError(
-                'taskUpdate',
-                'Required parameter "taskUpdate" was null or undefined when calling setTaskApiTasksTaskIdPatch().'
+                'nodeUpdate',
+                'Required parameter "nodeUpdate" was null or undefined when calling setTaskApiTasksTaskIdPatch().'
             );
         }
 
@@ -421,7 +421,7 @@ export class DefaultApi extends runtime.BaseAPI {
             method: 'PATCH',
             headers: headerParameters,
             query: queryParameters,
-            body: TaskUpdateToJSON(requestParameters['taskUpdate']),
+            body: NodeUpdateToJSON(requestParameters['nodeUpdate']),
         }, initOverrides);
 
         return new runtime.JSONApiResponse(response, (jsonValue) => OperationResultFromJSON(jsonValue));
diff --git a/client/generated/docs/DefaultApi.md b/client/generated/docs/DefaultApi.md
index 3018d1c..9bedff4 100644
--- a/client/generated/docs/DefaultApi.md
+++ b/client/generated/docs/DefaultApi.md
@@ -20,7 +20,7 @@ All URIs are relative to *http://localhost*
 
 ## addTaskApiTasksPost
 
-> TaskOut addTaskApiTasksPost(taskCreate)
+> NodeOut addTaskApiTasksPost(nodeCreate)
 
 Add Task
 
@@ -40,8 +40,8 @@ async function example() {
   const api = new DefaultApi();
 
   const body = {
-    // TaskCreate
-    taskCreate: ...,
+    // NodeCreate
+    nodeCreate: ...,
   } satisfies AddTaskApiTasksPostRequest;
 
   try {
@@ -61,11 +61,11 @@ example().catch(console.error);
 
 | Name | Type | Description  | Notes |
 |------------- | ------------- | ------------- | -------------|
-| **taskCreate** | [TaskCreate](TaskCreate.md) |  | |
+| **nodeCreate** | [NodeCreate](NodeCreate.md) |  | |
 
 ### Return type
 
-[**TaskOut**](TaskOut.md)
+[**NodeOut**](NodeOut.md)
 
 ### Authorization
 
@@ -88,7 +88,7 @@ No authorization required
 
 ## getTaskApiTasksTaskIdGet
 
-> TaskOut getTaskApiTasksTaskIdGet(taskId)
+> NodeOut getTaskApiTasksTaskIdGet(taskId)
 
 Get Task
 
@@ -133,7 +133,7 @@ example().catch(console.error);
 
 ### Return type
 
-[**TaskOut**](TaskOut.md)
+[**NodeOut**](NodeOut.md)
 
 ### Authorization
 
@@ -342,7 +342,7 @@ No authorization required
 
 ## listTasksApiTasksGet
 
-> TaskListOut listTasksApiTasksGet()
+> NodeListOut listTasksApiTasksGet()
 
 List Tasks
 
@@ -379,7 +379,7 @@ This endpoint does not need any parameter.
 
 ### Return type
 
-[**TaskListOut**](TaskListOut.md)
+[**NodeListOut**](NodeListOut.md)
 
 ### Authorization
 
@@ -540,7 +540,7 @@ No authorization required
 
 ## setTaskApiTasksTaskIdPatch
 
-> OperationResult setTaskApiTasksTaskIdPatch(taskId, taskUpdate)
+> OperationResult setTaskApiTasksTaskIdPatch(taskId, nodeUpdate)
 
 Set Task
 
@@ -562,8 +562,8 @@ async function example() {
   const body = {
     // string
     taskId: taskId_example,
-    // TaskUpdate
-    taskUpdate: ...,
+    // NodeUpdate
+    nodeUpdate: ...,
   } satisfies SetTaskApiTasksTaskIdPatchRequest;
 
   try {
@@ -584,7 +584,7 @@ example().catch(console.error);
 | Name | Type | Description  | Notes |
 |------------- | ------------- | ------------- | -------------|
 | **taskId** | `string` |  | [Defaults to `undefined`] |
-| **taskUpdate** | [TaskUpdate](TaskUpdate.md) |  | |
+| **nodeUpdate** | [NodeUpdate](NodeUpdate.md) |  | |
 
 ### Return type
 
diff --git a/client/generated/docs/NodeCreate.md b/client/generated/docs/NodeCreate.md
new file mode 100644
index 0000000..30f89e3
--- /dev/null
+++ b/client/generated/docs/NodeCreate.md
@@ -0,0 +1,47 @@
+
+# NodeCreate
+
+Node creation request.
+
+## Properties
+
+Name | Type
+------------ | -------------
+`text` | string
+`completed` | boolean
+`nodeType` | [NodeType](NodeType.md)
+`due` | number
+`id` | string
+`depends` | Array&lt;string&gt;
+`blocks` | Array&lt;string&gt;
+
+## Example
+
+```typescript
+import type { NodeCreate } from ''
+
+// TODO: Update the object below with actual values
+const example = {
+  "text": null,
+  "completed": null,
+  "nodeType": null,
+  "due": null,
+  "id": null,
+  "depends": null,
+  "blocks": null,
+} satisfies NodeCreate
+
+console.log(example)
+
+// Convert the instance to a JSON string
+const exampleJSON: string = JSON.stringify(example)
+console.log(exampleJSON)
+
+// Parse the JSON string back to an object
+const exampleParsed = JSON.parse(exampleJSON) as NodeCreate
+console.log(exampleParsed)
+```
+
+[[Back to top]](#) [[Back to API list]](../README.md#api-endpoints) [[Back to Model list]](../README.md#models) [[Back to README]](../README.md)
+
+
diff --git a/client/generated/docs/NodeListOut.md b/client/generated/docs/NodeListOut.md
new file mode 100644
index 0000000..18e6ce7
--- /dev/null
+++ b/client/generated/docs/NodeListOut.md
@@ -0,0 +1,39 @@
+
+# NodeListOut
+
+Node list response.
+
+## Properties
+
+Name | Type
+------------ | -------------
+`tasks` | [{ [key: string]: NodeOut; }](NodeOut.md)
+`dependencies` | [{ [key: string]: DependencyOut; }](DependencyOut.md)
+`hasCycles` | boolean
+
+## Example
+
+```typescript
+import type { NodeListOut } from ''
+
+// TODO: Update the object below with actual values
+const example = {
+  "tasks": null,
+  "dependencies": null,
+  "hasCycles": null,
+} satisfies NodeListOut
+
+console.log(example)
+
+// Convert the instance to a JSON string
+const exampleJSON: string = JSON.stringify(example)
+console.log(exampleJSON)
+
+// Parse the JSON string back to an object
+const exampleParsed = JSON.parse(exampleJSON) as NodeListOut
+console.log(exampleParsed)
+```
+
+[[Back to top]](#) [[Back to API list]](../README.md#api-endpoints) [[Back to Model list]](../README.md#models) [[Back to README]](../README.md)
+
+
diff --git a/client/generated/docs/NodeOut.md b/client/generated/docs/NodeOut.md
new file mode 100644
index 0000000..3d7df7b
--- /dev/null
+++ b/client/generated/docs/NodeOut.md
@@ -0,0 +1,59 @@
+
+# NodeOut
+
+Node response with calculated fields.
+
+## Properties
+
+Name | Type
+------------ | -------------
+`id` | string
+`text` | string
+`nodeType` | [NodeType](NodeType.md)
+`completed` | boolean
+`due` | number
+`createdAt` | number
+`updatedAt` | number
+`calculatedValue` | boolean
+`calculatedDue` | number
+`depsClear` | boolean
+`isActionable` | boolean
+`parents` | Array&lt;string&gt;
+`children` | Array&lt;string&gt;
+
+## Example
+
+```typescript
+import type { NodeOut } from ''
+
+// TODO: Update the object below with actual values
+const example = {
+  "id": null,
+  "text": null,
+  "nodeType": null,
+  "completed": null,
+  "due": null,
+  "createdAt": null,
+  "updatedAt": null,
+  "calculatedValue": null,
+  "calculatedDue": null,
+  "depsClear": null,
+  "isActionable": null,
+  "parents": null,
+  "children": null,
+} satisfies NodeOut
+
+console.log(example)
+
+// Convert the instance to a JSON string
+const exampleJSON: string = JSON.stringify(example)
+console.log(exampleJSON)
+
+// Parse the JSON string back to an object
+const exampleParsed = JSON.parse(exampleJSON) as NodeOut
+console.log(exampleParsed)
+```
+
+[[Back to top]](#) [[Back to API list]](../README.md#api-endpoints) [[Back to Model list]](../README.md#models) [[Back to README]](../README.md)
+
+
diff --git a/client/generated/docs/NodeType.md b/client/generated/docs/NodeType.md
new file mode 100644
index 0000000..1daba59
--- /dev/null
+++ b/client/generated/docs/NodeType.md
@@ -0,0 +1,33 @@
+
+# NodeType
+
+Node type labels.
+
+## Properties
+
+Name | Type
+------------ | -------------
+
+## Example
+
+```typescript
+import type { NodeType } from ''
+
+// TODO: Update the object below with actual values
+const example = {
+} satisfies NodeType
+
+console.log(example)
+
+// Convert the instance to a JSON string
+const exampleJSON: string = JSON.stringify(example)
+console.log(exampleJSON)
+
+// Parse the JSON string back to an object
+const exampleParsed = JSON.parse(exampleJSON) as NodeType
+console.log(exampleParsed)
+```
+
+[[Back to top]](#) [[Back to API list]](../README.md#api-endpoints) [[Back to Model list]](../README.md#models) [[Back to README]](../README.md)
+
+
diff --git a/client/generated/docs/NodeUpdate.md b/client/generated/docs/NodeUpdate.md
new file mode 100644
index 0000000..70fbde5
--- /dev/null
+++ b/client/generated/docs/NodeUpdate.md
@@ -0,0 +1,41 @@
+
+# NodeUpdate
+
+Node update request.
+
+## Properties
+
+Name | Type
+------------ | -------------
+`text` | string
+`completed` | boolean
+`nodeType` | [NodeType](NodeType.md)
+`due` | number
+
+## Example
+
+```typescript
+import type { NodeUpdate } from ''
+
+// TODO: Update the object below with actual values
+const example = {
+  "text": null,
+  "completed": null,
+  "nodeType": null,
+  "due": null,
+} satisfies NodeUpdate
+
+console.log(example)
+
+// Convert the instance to a JSON string
+const exampleJSON: string = JSON.stringify(example)
+console.log(exampleJSON)
+
+// Parse the JSON string back to an object
+const exampleParsed = JSON.parse(exampleJSON) as NodeUpdate
+console.log(exampleParsed)
+```
+
+[[Back to top]](#) [[Back to API list]](../README.md#api-endpoints) [[Back to Model list]](../README.md#models) [[Back to README]](../README.md)
+
+
diff --git a/client/generated/docs/ValidationError.md b/client/generated/docs/ValidationError.md
index fe92f21..d242d89 100644
--- a/client/generated/docs/ValidationError.md
+++ b/client/generated/docs/ValidationError.md
@@ -9,6 +9,8 @@ Name | Type
 `loc` | [Array&lt;LocationInner&gt;](LocationInner.md)
 `msg` | string
 `type` | string
+`input` | any
+`ctx` | object
 
 ## Example
 
@@ -20,6 +22,8 @@ const example = {
   "loc": null,
   "msg": null,
   "type": null,
+  "input": null,
+  "ctx": null,
 } satisfies ValidationError
 
 console.log(example)
diff --git a/client/generated/models/NodeCreate.ts b/client/generated/models/NodeCreate.ts
new file mode 100644
index 0000000..58d2e96
--- /dev/null
+++ b/client/generated/models/NodeCreate.ts
@@ -0,0 +1,124 @@
+/* tslint:disable */
+/* eslint-disable */
+/**
+ * DAG Todo API
+ * Task management with DAG dependencies and real-time updates
+ *
+ * The version of the OpenAPI document: 0.1.0
+ * 
+ *
+ * NOTE: This class is auto generated by OpenAPI Generator (https://openapi-generator.tech).
+ * https://openapi-generator.tech
+ * Do not edit the class manually.
+ */
+
+import { mapValues } from '../runtime';
+import type { NodeType } from './NodeType';
+import {
+    NodeTypeFromJSON,
+    NodeTypeFromJSONTyped,
+    NodeTypeToJSON,
+    NodeTypeToJSONTyped,
+} from './NodeType';
+
+/**
+ * Node creation request.
+ * @export
+ * @interface NodeCreate
+ */
+export interface NodeCreate {
+    /**
+     * 
+     * @type {string}
+     * @memberof NodeCreate
+     */
+    text?: string | null;
+    /**
+     * 
+     * @type {boolean}
+     * @memberof NodeCreate
+     */
+    completed?: boolean;
+    /**
+     * 
+     * @type {NodeType}
+     * @memberof NodeCreate
+     */
+    nodeType?: NodeType;
+    /**
+     * 
+     * @type {number}
+     * @memberof NodeCreate
+     */
+    due?: number | null;
+    /**
+     * 
+     * @type {string}
+     * @memberof NodeCreate
+     */
+    id: string;
+    /**
+     * 
+     * @type {Array<string>}
+     * @memberof NodeCreate
+     */
+    depends?: Array<string> | null;
+    /**
+     * 
+     * @type {Array<string>}
+     * @memberof NodeCreate
+     */
+    blocks?: Array<string> | null;
+}
+
+
+
+/**
+ * Check if a given object implements the NodeCreate interface.
+ */
+export function instanceOfNodeCreate(value: object): value is NodeCreate {
+    if (!('id' in value) || value['id'] === undefined) return false;
+    return true;
+}
+
+export function NodeCreateFromJSON(json: any): NodeCreate {
+    return NodeCreateFromJSONTyped(json, false);
+}
+
+export function NodeCreateFromJSONTyped(json: any, ignoreDiscriminator: boolean): NodeCreate {
+    if (json == null) {
+        return json;
+    }
+    return {
+        
+        'text': json['text'] == null ? undefined : json['text'],
+        'completed': json['completed'] == null ? undefined : json['completed'],
+        'nodeType': json['node_type'] == null ? undefined : NodeTypeFromJSON(json['node_type']),
+        'due': json['due'] == null ? undefined : json['due'],
+        'id': json['id'],
+        'depends': json['depends'] == null ? undefined : json['depends'],
+        'blocks': json['blocks'] == null ? undefined : json['blocks'],
+    };
+}
+
+export function NodeCreateToJSON(json: any): NodeCreate {
+    return NodeCreateToJSONTyped(json, false);
+}
+
+export function NodeCreateToJSONTyped(value?: NodeCreate | null, ignoreDiscriminator: boolean = false): any {
+    if (value == null) {
+        return value;
+    }
+
+    return {
+        
+        'text': value['text'],
+        'completed': value['completed'],
+        'node_type': NodeTypeToJSON(value['nodeType']),
+        'due': value['due'],
+        'id': value['id'],
+        'depends': value['depends'],
+        'blocks': value['blocks'],
+    };
+}
+
diff --git a/client/generated/models/NodeListOut.ts b/client/generated/models/NodeListOut.ts
new file mode 100644
index 0000000..6a97834
--- /dev/null
+++ b/client/generated/models/NodeListOut.ts
@@ -0,0 +1,99 @@
+/* tslint:disable */
+/* eslint-disable */
+/**
+ * DAG Todo API
+ * Task management with DAG dependencies and real-time updates
+ *
+ * The version of the OpenAPI document: 0.1.0
+ * 
+ *
+ * NOTE: This class is auto generated by OpenAPI Generator (https://openapi-generator.tech).
+ * https://openapi-generator.tech
+ * Do not edit the class manually.
+ */
+
+import { mapValues } from '../runtime';
+import type { NodeOut } from './NodeOut';
+import {
+    NodeOutFromJSON,
+    NodeOutFromJSONTyped,
+    NodeOutToJSON,
+    NodeOutToJSONTyped,
+} from './NodeOut';
+import type { DependencyOut } from './DependencyOut';
+import {
+    DependencyOutFromJSON,
+    DependencyOutFromJSONTyped,
+    DependencyOutToJSON,
+    DependencyOutToJSONTyped,
+} from './DependencyOut';
+
+/**
+ * Node list response.
+ * @export
+ * @interface NodeListOut
+ */
+export interface NodeListOut {
+    /**
+     * 
+     * @type {{ [key: string]: NodeOut; }}
+     * @memberof NodeListOut
+     */
+    tasks: { [key: string]: NodeOut; };
+    /**
+     * 
+     * @type {{ [key: string]: DependencyOut; }}
+     * @memberof NodeListOut
+     */
+    dependencies: { [key: string]: DependencyOut; };
+    /**
+     * 
+     * @type {boolean}
+     * @memberof NodeListOut
+     */
+    hasCycles: boolean;
+}
+
+/**
+ * Check if a given object implements the NodeListOut interface.
+ */
+export function instanceOfNodeListOut(value: object): value is NodeListOut {
+    if (!('tasks' in value) || value['tasks'] === undefined) return false;
+    if (!('dependencies' in value) || value['dependencies'] === undefined) return false;
+    if (!('hasCycles' in value) || value['hasCycles'] === undefined) return false;
+    return true;
+}
+
+export function NodeListOutFromJSON(json: any): NodeListOut {
+    return NodeListOutFromJSONTyped(json, false);
+}
+
+export function NodeListOutFromJSONTyped(json: any, ignoreDiscriminator: boolean): NodeListOut {
+    if (json == null) {
+        return json;
+    }
+    return {
+        
+        'tasks': (mapValues(json['tasks'], NodeOutFromJSON)),
+        'dependencies': (mapValues(json['dependencies'], DependencyOutFromJSON)),
+        'hasCycles': json['has_cycles'],
+    };
+}
+
+export function NodeListOutToJSON(json: any): NodeListOut {
+    return NodeListOutToJSONTyped(json, false);
+}
+
+export function NodeListOutToJSONTyped(value?: NodeListOut | null, ignoreDiscriminator: boolean = false): any {
+    if (value == null) {
+        return value;
+    }
+
+    return {
+        
+        'tasks': (mapValues(value['tasks'], NodeOutToJSON)),
+        'dependencies': (mapValues(value['dependencies'], DependencyOutToJSON)),
+        'has_cycles': value['hasCycles'],
+    };
+}
+
diff --git a/client/generated/models/NodeOut.ts b/client/generated/models/NodeOut.ts
new file mode 100644
index 0000000..b2cec39
--- /dev/null
+++ b/client/generated/models/NodeOut.ts
@@ -0,0 +1,184 @@
+/* tslint:disable */
+/* eslint-disable */
+/**
+ * DAG Todo API
+ * Task management with DAG dependencies and real-time updates
+ *
+ * The version of the OpenAPI document: 0.1.0
+ * 
+ *
+ * NOTE: This class is auto generated by OpenAPI Generator (https://openapi-generator.tech).
+ * https://openapi-generator.tech
+ * Do not edit the class manually.
+ */
+
+import { mapValues } from '../runtime';
+import type { NodeType } from './NodeType';
+import {
+    NodeTypeFromJSON,
+    NodeTypeFromJSONTyped,
+    NodeTypeToJSON,
+    NodeTypeToJSONTyped,
+} from './NodeType';
+
+/**
+ * Node response with calculated fields.
+ * @export
+ * @interface NodeOut
+ */
+export interface NodeOut {
+    /**
+     * 
+     * @type {string}
+     * @memberof NodeOut
+     */
+    id: string;
+    /**
+     * 
+     * @type {string}
+     * @memberof NodeOut
+     */
+    text: string;
+    /**
+     * 
+     * @type {NodeType}
+     * @memberof NodeOut
+     */
+    nodeType: NodeType;
+    /**
+     * 
+     * @type {boolean}
+     * @memberof NodeOut
+     */
+    completed: boolean | null;
+    /**
+     * 
+     * @type {number}
+     * @memberof NodeOut
+     */
+    due: number | null;
+    /**
+     * 
+     * @type {number}
+     * @memberof NodeOut
+     */
+    createdAt: number | null;
+    /**
+     * 
+     * @type {number}
+     * @memberof NodeOut
+     */
+    updatedAt: number | null;
+    /**
+     * 
+     * @type {boolean}
+     * @memberof NodeOut
+     */
+    calculatedValue: boolean | null;
+    /**
+     * 
+     * @type {number}
+     * @memberof NodeOut
+     */
+    calculatedDue: number | null;
+    /**
+     * 
+     * @type {boolean}
+     * @memberof NodeOut
+     */
+    depsClear: boolean | null;
+    /**
+     * 
+     * @type {boolean}
+     * @memberof NodeOut
+     */
+    isActionable: boolean | null;
+    /**
+     * 
+     * @type {Array<string>}
+     * @memberof NodeOut
+     */
+    parents: Array<string>;
+    /**
+     * 
+     * @type {Array<string>}
+     * @memberof NodeOut
+     */
+    children: Array<string>;
+}
+
+
+
+/**
+ * Check if a given object implements the NodeOut interface.
+ */
+export function instanceOfNodeOut(value: object): value is NodeOut {
+    if (!('id' in value) || value['id'] === undefined) return false;
+    if (!('text' in value) || value['text'] === undefined) return false;
+    if (!('nodeType' in value) || value['nodeType'] === undefined) return false;
+    if (!('completed' in value) || value['completed'] === undefined) return false;
+    if (!('due' in value) || value['due'] === undefined) return false;
+    if (!('createdAt' in value) || value['createdAt'] === undefined) return false;
+    if (!('updatedAt' in value) || value['updatedAt'] === undefined) return false;
+    if (!('calculatedValue' in value) || value['calculatedValue'] === undefined) return false;
+    if (!('calculatedDue' in value) || value['calculatedDue'] === undefined) return false;
+    if (!('depsClear' in value) || value['depsClear'] === undefined) return false;
+    if (!('isActionable' in value) || value['isActionable'] === undefined) return false;
+    if (!('parents' in value) || value['parents'] === undefined) return false;
+    if (!('children' in value) || value['children'] === undefined) return false;
+    return true;
+}
+
+export function NodeOutFromJSON(json: any): NodeOut {
+    return NodeOutFromJSONTyped(json, false);
+}
+
+export function NodeOutFromJSONTyped(json: any, ignoreDiscriminator: boolean): NodeOut {
+    if (json == null) {
+        return json;
+    }
+    return {
+        
+        'id': json['id'],
+        'text': json['text'],
+        'nodeType': NodeTypeFromJSON(json['node_type']),
+        'completed': json['completed'],
+        'due': json['due'],
+        'createdAt': json['created_at'],
+        'updatedAt': json['updated_at'],
+        'calculatedValue': json['calculated_value'],
+        'calculatedDue': json['calculated_due'],
+        'depsClear': json['deps_clear'],
+        'isActionable': json['is_actionable'],
+        'parents': json['parents'],
+        'children': json['children'],
+    };
+}
+
+export function NodeOutToJSON(json: any): NodeOut {
+    return NodeOutToJSONTyped(json, false);
+}
+
+export function NodeOutToJSONTyped(value?: NodeOut | null, ignoreDiscriminator: boolean = false): any {
+    if (value == null) {
+        return value;
+    }
+
+    return {
+        
+        'id': value['id'],
+        'text': value['text'],
+        'node_type': NodeTypeToJSON(value['nodeType']),
+        'completed': value['completed'],
+        'due': value['due'],
+        'created_at': value['createdAt'],
+        'updated_at': value['updatedAt'],
+        'calculated_value': value['calculatedValue'],
+        'calculated_due': value['calculatedDue'],
+        'deps_clear': value['depsClear'],
+        'is_actionable': value['isActionable'],
+        'parents': value['parents'],
+        'children': value['children'],
+    };
+}
+
diff --git a/client/generated/models/NodeType.ts b/client/generated/models/NodeType.ts
new file mode 100644
index 0000000..c2b9eab
--- /dev/null
+++ b/client/generated/models/NodeType.ts
@@ -0,0 +1,56 @@
+/* tslint:disable */
+/* eslint-disable */
+/**
+ * DAG Todo API
+ * Task management with DAG dependencies and real-time updates
+ *
+ * The version of the OpenAPI document: 0.1.0
+ * 
+ *
+ * NOTE: This class is auto generated by OpenAPI Generator (https://openapi-generator.tech).
+ * https://openapi-generator.tech
+ * Do not edit the class manually.
+ */
+
+
+/**
+ * Node type labels.
+ * @export
+ */
+export const NodeType = {
+    Task: 'Task',
+    And: 'And',
+    Or: 'Or',
+    Not: 'Not',
+    ExactlyOne: 'ExactlyOne'
+} as const;
+export type NodeType = typeof NodeType[keyof typeof NodeType];
+
+
+export function instanceOfNodeType(value: any): boolean {
+    for (const key in NodeType) {
+        if (Object.prototype.hasOwnProperty.call(NodeType, key)) {
+            if (NodeType[key as keyof typeof NodeType] === value) {
+                return true;
+            }
+        }
+    }
+    return false;
+}
+
+export function NodeTypeFromJSON(json: any): NodeType {
+    return NodeTypeFromJSONTyped(json, false);
+}
+
+export function NodeTypeFromJSONTyped(json: any, ignoreDiscriminator: boolean): NodeType {
+    return json as NodeType;
+}
+
+export function NodeTypeToJSON(value?: NodeType | null): any {
+    return value as any;
+}
+
+export function NodeTypeToJSONTyped(value: any, ignoreDiscriminator: boolean): NodeType {
+    return value as NodeType;
+}
+
diff --git a/client/generated/models/NodeUpdate.ts b/client/generated/models/NodeUpdate.ts
new file mode 100644
index 0000000..286ecf7
--- /dev/null
+++ b/client/generated/models/NodeUpdate.ts
@@ -0,0 +1,99 @@
+/* tslint:disable */
+/* eslint-disable */
+/**
+ * DAG Todo API
+ * Task management with DAG dependencies and real-time updates
+ *
+ * The version of the OpenAPI document: 0.1.0
+ * 
+ *
+ * NOTE: This class is auto generated by OpenAPI Generator (https://openapi-generator.tech).
+ * https://openapi-generator.tech
+ * Do not edit the class manually.
+ */
+
+import { mapValues } from '../runtime';
+import type { NodeType } from './NodeType';
+import {
+    NodeTypeFromJSON,
+    NodeTypeFromJSONTyped,
+    NodeTypeToJSON,
+    NodeTypeToJSONTyped,
+} from './NodeType';
+
+/**
+ * Node update request.
+ * @export
+ * @interface NodeUpdate
+ */
+export interface NodeUpdate {
+    /**
+     * 
+     * @type {string}
+     * @memberof NodeUpdate
+     */
+    text?: string | null;
+    /**
+     * 
+     * @type {boolean}
+     * @memberof NodeUpdate
+     */
+    completed?: boolean | null;
+    /**
+     * 
+     * @type {NodeType}
+     * @memberof NodeUpdate
+     */
+    nodeType?: NodeType | null;
+    /**
+     * 
+     * @type {number}
+     * @memberof NodeUpdate
+     */
+    due?: number | null;
+}
+
+
+
+/**
+ * Check if a given object implements the NodeUpdate interface.
+ */
+export function instanceOfNodeUpdate(value: object): value is NodeUpdate {
+    return true;
+}
+
+export function NodeUpdateFromJSON(json: any): NodeUpdate {
+    return NodeUpdateFromJSONTyped(json, false);
+}
+
+export function NodeUpdateFromJSONTyped(json: any, ignoreDiscriminator: boolean): NodeUpdate {
+    if (json == null) {
+        return json;
+    }
+    return {
+        
+        'text': json['text'] == null ? undefined : json['text'],
+        'completed': json['completed'] == null ? undefined : json['completed'],
+        'nodeType': json['node_type'] == null ? undefined : NodeTypeFromJSON(json['node_type']),
+        'due': json['due'] == null ? undefined : json['due'],
+    };
+}
+
+export function NodeUpdateToJSON(json: any): NodeUpdate {
+    return NodeUpdateToJSONTyped(json, false);
+}
+
+export function NodeUpdateToJSONTyped(value?: NodeUpdate | null, ignoreDiscriminator: boolean = false): any {
+    if (value == null) {
+        return value;
+    }
+
+    return {
+        
+        'text': value['text'],
+        'completed': value['completed'],
+        'node_type': NodeTypeToJSON(value['nodeType']),
+        'due': value['due'],
+    };
+}
+
diff --git a/client/generated/models/ValidationError.ts b/client/generated/models/ValidationError.ts
index c37323e..713374a 100644
--- a/client/generated/models/ValidationError.ts
+++ b/client/generated/models/ValidationError.ts
@@ -45,6 +45,18 @@ export interface ValidationError {
      * @memberof ValidationError
      */
     type: string;
+    /**
+     * 
+     * @type {any}
+     * @memberof ValidationError
+     */
+    input?: any | null;
+    /**
+     * 
+     * @type {object}
+     * @memberof ValidationError
+     */
+    ctx?: object;
 }
 
 /**
@@ -70,6 +82,8 @@ export function ValidationErrorFromJSONTyped(json: any, ignoreDiscriminator: boo
         'loc': ((json['loc'] as Array<any>).map(LocationInnerFromJSON)),
         'msg': json['msg'],
         'type': json['type'],
+        'input': json['input'] == null ? undefined : json['input'],
+        'ctx': json['ctx'] == null ? undefined : json['ctx'],
     };
 }
 
@@ -87,6 +101,8 @@ export function ValidationErrorToJSONTyped(value?: ValidationError | null, ignor
         'loc': ((value['loc'] as Array<any>).map(LocationInnerToJSON)),
         'msg': value['msg'],
         'type': value['type'],
+        'input': value['input'],
+        'ctx': value['ctx'],
     };
 }
 
diff --git a/client/generated/models/index.ts b/client/generated/models/index.ts
index 5ec6f06..d48ab99 100644
--- a/client/generated/models/index.ts
+++ b/client/generated/models/index.ts
@@ -4,10 +4,11 @@ export * from './DependencyOut';
 export * from './HTTPValidationError';
 export * from './LinkRequest';
 export * from './LocationInner';
+export * from './NodeCreate';
+export * from './NodeListOut';
+export * from './NodeOut';
+export * from './NodeType';
+export * from './NodeUpdate';
 export * from './OperationResult';
 export * from './RenameRequest';
-export * from './TaskCreate';
-export * from './TaskListOut';
-export * from './TaskOut';
-export * from './TaskUpdate';
 export * from './ValidationError';
diff --git a/client/openapi.json b/client/openapi.json
index dc49624..64b5ecb 100644
--- a/client/openapi.json
+++ b/client/openapi.json
@@ -1 +1 @@
-{"openapi":"3.1.0","info":{"title":"DAG Todo API","description":"Task management with DAG dependencies and real-time updates","version":"0.1.0"},"paths":{"/api/tasks":{"get":{"summary":"List Tasks","description":"List all tasks with computed properties.","operationId":"list_tasks_api_tasks_get","responses":{"200":{"description":"Successful Response","content":{"application/json":{"schema":{"$ref":"#/components/schemas/TaskListOut"}}}}}},"post":{"summary":"Add Task","description":"Create a new task.","operationId":"add_task_api_tasks_post","requestBody":{"content":{"application/json":{"schema":{"$ref":"#/components/schemas/TaskCreate"}}},"required":true},"responses":{"200":{"description":"Successful Response","content":{"application/json":{"schema":{"$ref":"#/components/schemas/TaskOut"}}}},"422":{"description":"Validation Error","content":{"application/json":{"schema":{"$ref":"#/components/schemas/HTTPValidationError"}}}}}}},"/api/tasks/{task_id}":{"get":{"summary":"Get Task","description":"Get a single task with computed properties.","operationId":"get_task_api_tasks__task_id__get","parameters":[{"name":"task_id","in":"path","required":true,"schema":{"type":"string","title":"Task Id"}}],"responses":{"200":{"description":"Successful Response","content":{"application/json":{"schema":{"$ref":"#/components/schemas/TaskOut"}}}},"422":{"description":"Validation Error","content":{"application/json":{"schema":{"$ref":"#/components/schemas/HTTPValidationError"}}}}}},"patch":{"summary":"Set Task","description":"Update a task's properties.","operationId":"set_task_api_tasks__task_id__patch","parameters":[{"name":"task_id","in":"path","required":true,"schema":{"type":"string","title":"Task Id"}}],"requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"#/components/schemas/TaskUpdate"}}}},"responses":{"200":{"description":"Successful Response","content":{"application/json":{"schema":{"$ref":"#/components/schemas/OperationResult"}}}},"422":{"description":"Validation Error","content":{"application/json":{"schema":{"$ref":"#/components/schemas/HTTPValidationError"}}}}}},"delete":{"summary":"Remove Task","description":"Delete a task and its edges.","operationId":"remove_task_api_tasks__task_id__delete","parameters":[{"name":"task_id","in":"path","required":true,"schema":{"type":"string","title":"Task Id"}}],"responses":{"200":{"description":"Successful Response","content":{"application/json":{"schema":{"$ref":"#/components/schemas/OperationResult"}}}},"422":{"description":"Validation Error","content":{"application/json":{"schema":{"$ref":"#/components/schemas/HTTPValidationError"}}}}}}},"/api/tasks/{task_id}/rename":{"post":{"summary":"Rename Task","description":"Rename a task (change its ID).","operationId":"rename_task_api_tasks__task_id__rename_post","parameters":[{"name":"task_id","in":"path","required":true,"schema":{"type":"string","title":"Task Id"}}],"requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"#/components/schemas/RenameRequest"}}}},"responses":{"200":{"description":"Successful Response","content":{"application/json":{"schema":{"$ref":"#/components/schemas/OperationResult"}}}},"422":{"description":"Validation Error","content":{"application/json":{"schema":{"$ref":"#/components/schemas/HTTPValidationError"}}}}}}},"/api/links":{"post":{"summary":"Link Tasks","description":"Create a dependency: from_id depends on to_id.","operationId":"link_tasks_api_links_post","requestBody":{"content":{"application/json":{"schema":{"$ref":"#/components/schemas/LinkRequest"}}},"required":true},"responses":{"200":{"description":"Successful Response","content":{"application/json":{"schema":{"$ref":"#/components/schemas/DependencyOut"}}}},"422":{"description":"Validation Error","content":{"application/json":{"schema":{"$ref":"#/components/schemas/HTTPValidationError"}}}}}},"delete":{"summary":"Unlink Tasks","description":"Remove a dependency.","operationId":"unlink_tasks_api_links_delete","requestBody":{"content":{"application/json":{"schema":{"$ref":"#/components/schemas/LinkRequest"}}},"required":true},"responses":{"200":{"description":"Successful Response","content":{"application/json":{"schema":{"$ref":"#/components/schemas/OperationResult"}}}},"422":{"description":"Validation Error","content":{"application/json":{"schema":{"$ref":"#/components/schemas/HTTPValidationError"}}}}}}},"/api/tasks/subscribe":{"get":{"summary":"Subscribe Tasks","description":"Subscribe to real-time task updates via SSE.","operationId":"subscribe_tasks_api_tasks_subscribe_get","responses":{"200":{"description":"Successful Response","content":{"application/json":{"schema":{}}}}}}},"/api/init":{"post":{"summary":"Init Db","description":"Initialize the database schema and run migrations.","operationId":"init_db_api_init_post","responses":{"200":{"description":"Successful Response","content":{"application/json":{"schema":{"$ref":"#/components/schemas/OperationResult"}}}}}}},"/health":{"get":{"summary":"Health","description":"Health check endpoint.","operationId":"health_health_get","responses":{"200":{"description":"Successful Response","content":{"application/json":{"schema":{}}}}}}}},"components":{"schemas":{"DependencyOut":{"properties":{"id":{"type":"string","title":"Id"},"from_id":{"type":"string","title":"From Id"},"to_id":{"type":"string","title":"To Id"}},"type":"object","required":["id","from_id","to_id"],"title":"DependencyOut","description":"Dependency relationship."},"HTTPValidationError":{"properties":{"detail":{"items":{"$ref":"#/components/schemas/ValidationError"},"type":"array","title":"Detail"}},"type":"object","title":"HTTPValidationError"},"LinkRequest":{"properties":{"from_id":{"type":"string","title":"From Id"},"to_id":{"type":"string","title":"To Id"}},"type":"object","required":["from_id","to_id"],"title":"LinkRequest","description":"Link/unlink request."},"OperationResult":{"properties":{"success":{"type":"boolean","title":"Success"},"message":{"anyOf":[{"type":"string"},{"type":"null"}],"title":"Message"}},"type":"object","required":["success"],"title":"OperationResult","description":"Generic operation result."},"RenameRequest":{"properties":{"new_id":{"type":"string","title":"New Id"}},"type":"object","required":["new_id"],"title":"RenameRequest","description":"Rename request."},"TaskCreate":{"properties":{"text":{"anyOf":[{"type":"string"},{"type":"null"}],"title":"Text"},"completed":{"type":"boolean","title":"Completed","default":false},"inferred":{"type":"boolean","title":"Inferred","default":false},"due":{"anyOf":[{"type":"integer"},{"type":"null"}],"title":"Due"},"id":{"type":"string","title":"Id"},"depends":{"anyOf":[{"items":{"type":"string"},"type":"array"},{"type":"null"}],"title":"Depends"},"blocks":{"anyOf":[{"items":{"type":"string"},"type":"array"},{"type":"null"}],"title":"Blocks"}},"type":"object","required":["id"],"title":"TaskCreate","description":"Task creation request."},"TaskListOut":{"properties":{"tasks":{"additionalProperties":{"$ref":"#/components/schemas/TaskOut"},"type":"object","title":"Tasks"},"dependencies":{"additionalProperties":{"$ref":"#/components/schemas/DependencyOut"},"type":"object","title":"Dependencies"},"has_cycles":{"type":"boolean","title":"Has Cycles"}},"type":"object","required":["tasks","dependencies","has_cycles"],"title":"TaskListOut","description":"Task list response."},"TaskOut":{"properties":{"id":{"type":"string","title":"Id"},"text":{"type":"string","title":"Text"},"completed":{"type":"boolean","title":"Completed"},"inferred":{"type":"boolean","title":"Inferred"},"due":{"anyOf":[{"type":"integer"},{"type":"null"}],"title":"Due"},"created_at":{"anyOf":[{"type":"integer"},{"type":"null"}],"title":"Created At"},"updated_at":{"anyOf":[{"type":"integer"},{"type":"null"}],"title":"Updated At"},"calculated_completed":{"anyOf":[{"type":"boolean"},{"type":"null"}],"title":"Calculated Completed"},"calculated_due":{"anyOf":[{"type":"integer"},{"type":"null"}],"title":"Calculated Due"},"deps_clear":{"anyOf":[{"type":"boolean"},{"type":"null"}],"title":"Deps Clear"},"parents":{"items":{"type":"string"},"type":"array","title":"Parents"},"children":{"items":{"type":"string"},"type":"array","title":"Children"}},"type":"object","required":["id","text","completed","inferred","due","created_at","updated_at","calculated_completed","calculated_due","deps_clear","parents","children"],"title":"TaskOut","description":"Task response with calculated fields."},"TaskUpdate":{"properties":{"text":{"anyOf":[{"type":"string"},{"type":"null"}],"title":"Text"},"completed":{"anyOf":[{"type":"boolean"},{"type":"null"}],"title":"Completed"},"inferred":{"anyOf":[{"type":"boolean"},{"type":"null"}],"title":"Inferred"},"due":{"anyOf":[{"type":"integer"},{"type":"null"}],"title":"Due"}},"type":"object","title":"TaskUpdate","description":"Task update request."},"ValidationError":{"properties":{"loc":{"items":{"anyOf":[{"type":"string"},{"type":"integer"}]},"type":"array","title":"Location"},"msg":{"type":"string","title":"Message"},"type":{"type":"string","title":"Error Type"}},"type":"object","required":["loc","msg","type"],"title":"ValidationError"}}}}
\ No newline at end of file
+{"openapi":"3.1.0","info":{"title":"DAG Todo API","description":"Task management with DAG dependencies and real-time updates","version":"0.1.0"},"paths":{"/api/tasks/subscribe":{"get":{"summary":"Subscribe Tasks","description":"Subscribe to real-time task updates via SSE.","operationId":"subscribe_tasks_api_tasks_subscribe_get","responses":{"200":{"description":"Successful Response","content":{"application/json":{"schema":{}}}}}}},"/api/tasks":{"get":{"summary":"List Tasks","description":"List all tasks with computed properties.","operationId":"list_tasks_api_tasks_get","responses":{"200":{"description":"Successful Response","content":{"application/json":{"schema":{"$ref":"#/components/schemas/NodeListOut"}}}}}},"post":{"summary":"Add Task","description":"Create a new task.","operationId":"add_task_api_tasks_post","requestBody":{"content":{"application/json":{"schema":{"$ref":"#/components/schemas/NodeCreate"}}},"required":true},"responses":{"200":{"description":"Successful Response","content":{"application/json":{"schema":{"$ref":"#/components/schemas/NodeOut"}}}},"422":{"description":"Validation Error","content":{"application/json":{"schema":{"$ref":"#/components/schemas/HTTPValidationError"}}}}}}},"/api/tasks/{task_id}":{"get":{"summary":"Get Task","description":"Get a single task with computed properties.","operationId":"get_task_api_tasks__task_id__get","parameters":[{"name":"task_id","in":"path","required":true,"schema":{"type":"string","title":"Task Id"}}],"responses":{"200":{"description":"Successful Response","content":{"application/json":{"schema":{"$ref":"#/components/schemas/NodeOut"}}}},"422":{"description":"Validation Error","content":{"application/json":{"schema":{"$ref":"#/components/schemas/HTTPValidationError"}}}}}},"patch":{"summary":"Set Task","description":"Update a task's properties.","operationId":"set_task_api_tasks__task_id__patch","parameters":[{"name":"task_id","in":"path","required":true,"schema":{"type":"string","title":"Task Id"}}],"requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"#/components/schemas/NodeUpdate"}}}},"responses":{"200":{"description":"Successful Response","content":{"application/json":{"schema":{"$ref":"#/components/schemas/OperationResult"}}}},"422":{"description":"Validation Error","content":{"application/json":{"schema":{"$ref":"#/components/schemas/HTTPValidationError"}}}}}},"delete":{"summary":"Remove Task","description":"Delete a task and its edges.","operationId":"remove_task_api_tasks__task_id__delete","parameters":[{"name":"task_id","in":"path","required":true,"schema":{"type":"string","title":"Task Id"}}],"responses":{"200":{"description":"Successful Response","content":{"application/json":{"schema":{"$ref":"#/components/schemas/OperationResult"}}}},"422":{"description":"Validation Error","content":{"application/json":{"schema":{"$ref":"#/components/schemas/HTTPValidationError"}}}}}}},"/api/tasks/{task_id}/rename":{"post":{"summary":"Rename Task","description":"Rename a task (change its ID).","operationId":"rename_task_api_tasks__task_id__rename_post","parameters":[{"name":"task_id","in":"path","required":true,"schema":{"type":"string","title":"Task Id"}}],"requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"#/components/schemas/RenameRequest"}}}},"responses":{"200":{"description":"Successful Response","content":{"application/json":{"schema":{"$ref":"#/components/schemas/OperationResult"}}}},"422":{"description":"Validation Error","content":{"application/json":{"schema":{"$ref":"#/components/schemas/HTTPValidationError"}}}}}}},"/api/links":{"post":{"summary":"Link Tasks","description":"Create a dependency: from_id depends on to_id.","operationId":"link_tasks_api_links_post","requestBody":{"content":{"application/json":{"schema":{"$ref":"#/components/schemas/LinkRequest"}}},"required":true},"responses":{"200":{"description":"Successful Response","content":{"application/json":{"schema":{"$ref":"#/components/schemas/DependencyOut"}}}},"422":{"description":"Validation Error","content":{"application/json":{"schema":{"$ref":"#/components/schemas/HTTPValidationError"}}}}}},"delete":{"summary":"Unlink Tasks","description":"Remove a dependency.","operationId":"unlink_tasks_api_links_delete","requestBody":{"content":{"application/json":{"schema":{"$ref":"#/components/schemas/LinkRequest"}}},"required":true},"responses":{"200":{"description":"Successful Response","content":{"application/json":{"schema":{"$ref":"#/components/schemas/OperationResult"}}}},"422":{"description":"Validation Error","content":{"application/json":{"schema":{"$ref":"#/components/schemas/HTTPValidationError"}}}}}}},"/api/init":{"post":{"summary":"Init Db","description":"Initialize the database schema and run migrations.","operationId":"init_db_api_init_post","responses":{"200":{"description":"Successful Response","content":{"application/json":{"schema":{"$ref":"#/components/schemas/OperationResult"}}}}}}},"/health":{"get":{"summary":"Health","description":"Health check endpoint.","operationId":"health_health_get","responses":{"200":{"description":"Successful Response","content":{"application/json":{"schema":{}}}}}}}},"components":{"schemas":{"DependencyOut":{"properties":{"id":{"type":"string","title":"Id"},"from_id":{"type":"string","title":"From Id"},"to_id":{"type":"string","title":"To Id"}},"type":"object","required":["id","from_id","to_id"],"title":"DependencyOut","description":"Dependency relationship."},"HTTPValidationError":{"properties":{"detail":{"items":{"$ref":"#/components/schemas/ValidationError"},"type":"array","title":"Detail"}},"type":"object","title":"HTTPValidationError"},"LinkRequest":{"properties":{"from_id":{"type":"string","title":"From Id"},"to_id":{"type":"string","title":"To Id"}},"type":"object","required":["from_id","to_id"],"title":"LinkRequest","description":"Link/unlink request."},"NodeCreate":{"properties":{"text":{"anyOf":[{"type":"string"},{"type":"null"}],"title":"Text"},"completed":{"type":"boolean","title":"Completed","default":false},"node_type":{"$ref":"#/components/schemas/NodeType","default":"Task"},"due":{"anyOf":[{"type":"integer"},{"type":"null"}],"title":"Due"},"id":{"type":"string","title":"Id"},"depends":{"anyOf":[{"items":{"type":"string"},"type":"array"},{"type":"null"}],"title":"Depends"},"blocks":{"anyOf":[{"items":{"type":"string"},"type":"array"},{"type":"null"}],"title":"Blocks"}},"type":"object","required":["id"],"title":"NodeCreate","description":"Node creation request."},"NodeListOut":{"properties":{"tasks":{"additionalProperties":{"$ref":"#/components/schemas/NodeOut"},"type":"object","title":"Tasks"},"dependencies":{"additionalProperties":{"$ref":"#/components/schemas/DependencyOut"},"type":"object","title":"Dependencies"},"has_cycles":{"type":"boolean","title":"Has Cycles"}},"type":"object","required":["tasks","dependencies","has_cycles"],"title":"NodeListOut","description":"Node list response."},"NodeOut":{"properties":{"id":{"type":"string","title":"Id"},"text":{"type":"string","title":"Text"},"node_type":{"$ref":"#/components/schemas/NodeType"},"completed":{"anyOf":[{"type":"boolean"},{"type":"null"}],"title":"Completed"},"due":{"anyOf":[{"type":"integer"},{"type":"null"}],"title":"Due"},"created_at":{"anyOf":[{"type":"integer"},{"type":"null"}],"title":"Created At"},"updated_at":{"anyOf":[{"type":"integer"},{"type":"null"}],"title":"Updated At"},"calculated_value":{"anyOf":[{"type":"boolean"},{"type":"null"}],"title":"Calculated Value"},"calculated_due":{"anyOf":[{"type":"integer"},{"type":"null"}],"title":"Calculated Due"},"deps_clear":{"anyOf":[{"type":"boolean"},{"type":"null"}],"title":"Deps Clear"},"is_actionable":{"anyOf":[{"type":"boolean"},{"type":"null"}],"title":"Is Actionable"},"parents":{"items":{"type":"string"},"type":"array","title":"Parents"},"children":{"items":{"type":"string"},"type":"array","title":"Children"}},"type":"object","required":["id","text","node_type","completed","due","created_at","updated_at","calculated_value","calculated_due","deps_clear","is_actionable","parents","children"],"title":"NodeOut","description":"Node response with calculated fields."},"NodeType":{"type":"string","enum":["Task","And","Or","Not","ExactlyOne"],"title":"NodeType","description":"Node type labels."},"NodeUpdate":{"properties":{"text":{"anyOf":[{"type":"string"},{"type":"null"}],"title":"Text"},"completed":{"anyOf":[{"type":"boolean"},{"type":"null"}],"title":"Completed"},"node_type":{"anyOf":[{"$ref":"#/components/schemas/NodeType"},{"type":"null"}]},"due":{"anyOf":[{"type":"integer"},{"type":"null"}],"title":"Due"}},"type":"object","title":"NodeUpdate","description":"Node update request."},"OperationResult":{"properties":{"success":{"type":"boolean","title":"Success"},"message":{"anyOf":[{"type":"string"},{"type":"null"}],"title":"Message"}},"type":"object","required":["success"],"title":"OperationResult","description":"Generic operation result."},"RenameRequest":{"properties":{"new_id":{"type":"string","title":"New Id"}},"type":"object","required":["new_id"],"title":"RenameRequest","description":"Rename request."},"ValidationError":{"properties":{"loc":{"items":{"anyOf":[{"type":"string"},{"type":"integer"}]},"type":"array","title":"Location"},"msg":{"type":"string","title":"Message"},"type":{"type":"string","title":"Error Type"},"input":{"title":"Input"},"ctx":{"type":"object","title":"Context"}},"type":"object","required":["loc","msg","type"],"title":"ValidationError"}}}}
\ No newline at end of file
diff --git a/client/sse.ts b/client/sse.ts
index e7b8cb2..cd63e22 100644
--- a/client/sse.ts
+++ b/client/sse.ts
@@ -5,9 +5,9 @@
  * OpenAPI doesn't spec SSE, so this is manual.
  */
 
-import { TaskListOut, TaskListOutFromJSON } from './generated';
+import { NodeListOut, NodeListOutFromJSON } from './generated';
 
-export type TaskSubscriber = (data: TaskListOut) => void;
+export type TaskSubscriber = (data: NodeListOut) => void;
 
 export function subscribeToTasks(
   onUpdate: TaskSubscriber,
@@ -22,7 +22,7 @@ export function subscribeToTasks(
   const handler = (e: MessageEvent) => {
     try {
       const raw = JSON.parse(e.data);
-      onUpdate(TaskListOutFromJSON(raw));
+      onUpdate(NodeListOutFromJSON(raw));
     } catch (err) {
       console.error('Failed to parse SSE data:', err);
     }

---

# Frontend Changes

diff --git a/index.html b/index.html
index c365acd..71023cb 100644
--- a/index.html
+++ b/index.html
@@ -16,7 +16,7 @@
   <script>
     window.__CONFIG__ = {
       // Set to API URL to auto-connect on load, or leave empty/null for manual connection
-      defaultApiUrl: "/api"
+      defaultApiUrl: ""
     };
   </script>
 </head>
diff --git a/package-lock.json b/package-lock.json
index bc97d21..ea5824e 100644
--- a/package-lock.json
+++ b/package-lock.json
@@ -12,8 +12,10 @@
         "@blocknote/core": "^0.16.0",
         "@blocknote/mantine": "^0.16.0",
         "@blocknote/react": "^0.16.0",
+        "chrono-node": "^2.9.0",
         "date-fns": "^3.6.0",
         "react": "^18.3.1",
+        "react-datepicker": "^9.1.0",
         "react-dom": "^18.3.1",
         "stats.js": "^0.17.0",
         "tinykeys": "^3.0.0",
@@ -24,6 +26,7 @@
       },
       "devDependencies": {
         "@types/react": "^18.3.11",
+        "@types/react-datepicker": "^6.2.0",
         "@types/react-dom": "^18.3.0",
         "@types/stats.js": "^0.17.4",
         "@types/uuid": "^10.0.0",
@@ -2013,6 +2016,18 @@
         "csstype": "^3.2.2"
       }
     },
+    "node_modules/@types/react-datepicker": {
+      "version": "6.2.0",
+      "resolved": "https://registry.npmjs.org/@types/react-datepicker/-/react-datepicker-6.2.0.tgz",
+      "integrity": "sha512-+JtO4Fm97WLkJTH8j8/v3Ldh7JCNRwjMYjRaKh4KHH0M3jJoXtwiD3JBCsdlg3tsFIw9eQSqyAPeVDN2H2oM9Q==",
+      "dev": true,
+      "license": "MIT",
+      "dependencies": {
+        "@floating-ui/react": "^0.26.2",
+        "@types/react": "*",
+        "date-fns": "^3.3.1"
+      }
+    },
     "node_modules/@types/react-dom": {
       "version": "18.3.7",
       "resolved": "https://registry.npmjs.org/@types/react-dom/-/react-dom-18.3.7.tgz",
@@ -2859,6 +2874,15 @@
         "node": ">= 6"
       }
     },
+    "node_modules/chrono-node": {
+      "version": "2.9.0",
+      "resolved": "https://registry.npmjs.org/chrono-node/-/chrono-node-2.9.0.tgz",
+      "integrity": "sha512-glI4YY2Jy6JII5l3d5FN6rcrIbKSQqKPhWsIRYPK2IK8Mm4Q1ZZFdYIaDqglUNf7gNwG+kWIzTn0omzzE0VkvQ==",
+      "license": "MIT",
+      "engines": {
+        "node": "^12.20.0 || ^14.13.1 || >=16.0.0"
+      }
+    },
     "node_modules/clsx": {
       "version": "2.1.1",
       "resolved": "https://registry.npmjs.org/clsx/-/clsx-2.1.1.tgz",
@@ -7291,6 +7315,52 @@
         "node": ">=0.10.0"
       }
     },
+    "node_modules/react-datepicker": {
+      "version": "9.1.0",
+      "resolved": "https://registry.npmjs.org/react-datepicker/-/react-datepicker-9.1.0.tgz",
+      "integrity": "sha512-lOp+m5bc+ttgtB5MHEjwiVu4nlp4CvJLS/PG1OiOe5pmg9kV73pEqO8H0Geqvg2E8gjqTaL9eRhSe+ZpeKP3nA==",
+      "license": "MIT",
+      "dependencies": {
+        "@floating-ui/react": "^0.27.15",
+        "clsx": "^2.1.1",
+        "date-fns": "^4.1.0"
+      },
+      "peerDependencies": {
+        "date-fns-tz": "^3.0.0",
+        "react": "^16.9.0 || ^17 || ^18 || ^19 || ^19.0.0-rc",
+        "react-dom": "^16.9.0 || ^17 || ^18 || ^19 || ^19.0.0-rc"
+      },
+      "peerDependenciesMeta": {
+        "date-fns-tz": {
+          "optional": true
+        }
+      }
+    },
+    "node_modules/react-datepicker/node_modules/@floating-ui/react": {
+      "version": "0.27.17",
+      "resolved": "https://registry.npmjs.org/@floating-ui/react/-/react-0.27.17.tgz",
+      "integrity": "sha512-LGVZKHwmWGg6MRHjLLgsfyaX2y2aCNgnD1zT/E6B+/h+vxg+nIJUqHPAlTzsHDyqdgEpJ1Np5kxWuFEErXzoGg==",
+      "license": "MIT",
+      "dependencies": {
+        "@floating-ui/react-dom": "^2.1.7",
+        "@floating-ui/utils": "^0.2.10",
+        "tabbable": "^6.0.0"
+      },
+      "peerDependencies": {
+        "react": ">=17.0.0",
+        "react-dom": ">=17.0.0"
+      }
+    },
+    "node_modules/react-datepicker/node_modules/date-fns": {
+      "version": "4.1.0",
+      "resolved": "https://registry.npmjs.org/date-fns/-/date-fns-4.1.0.tgz",
+      "integrity": "sha512-Ukq0owbQXxa/U3EGtsdVBkR1w7KOQ5gIBqdH2hkvknzZPYvBxb/aa6E8L7tmjFtkwZBu3UXBbjIgPo/Ez4xaNg==",
+      "license": "MIT",
+      "funding": {
+        "type": "github",
+        "url": "https://github.com/sponsors/kossnocorp"
+      }
+    },
     "node_modules/react-dom": {
       "version": "18.3.1",
       "resolved": "https://registry.npmjs.org/react-dom/-/react-dom-18.3.1.tgz",
@@ -8417,7 +8487,7 @@
     },
     "node_modules/todo-client": {
       "version": "0.1.0",
-      "resolved": "git+ssh://git@github.com/shiukaheng/todo.git#c55a250e2af1ba1bd929e4376f46a98cbff85afa",
+      "resolved": "git+ssh://git@github.com/shiukaheng/todo.git#38f84662ebc6cb0cc5bb14c783c9463ce80b4d97",
       "license": "MIT"
     },
     "node_modules/trim-lines": {
diff --git a/package.json b/package.json
index c2b454b..30c0a81 100644
--- a/package.json
+++ b/package.json
@@ -12,6 +12,7 @@
   },
   "devDependencies": {
     "@types/react": "^18.3.11",
+    "@types/react-datepicker": "^6.2.0",
     "@types/react-dom": "^18.3.0",
     "@types/stats.js": "^0.17.4",
     "@types/uuid": "^10.0.0",
@@ -36,8 +37,10 @@
     "@blocknote/core": "^0.16.0",
     "@blocknote/mantine": "^0.16.0",
     "@blocknote/react": "^0.16.0",
+    "chrono-node": "^2.9.0",
     "date-fns": "^3.6.0",
     "react": "^18.3.1",
+    "react-datepicker": "^9.1.0",
     "react-dom": "^18.3.1",
     "stats.js": "^0.17.0",
     "tinykeys": "^3.0.0",
diff --git a/src/commander/ui/CommandPlane.tsx b/src/commander/ui/CommandPlane.tsx
index c10441f..9a502ed 100644
--- a/src/commander/ui/CommandPlane.tsx
+++ b/src/commander/ui/CommandPlane.tsx
@@ -116,6 +116,8 @@ export function CommandPlane({ controller }: CommandPlaneProps) {
                     className="flex-1 bg-transparent ml-1 text-white outline-none text-base"
                     placeholder=""
                     autoComplete="off"
+                    autoCapitalize="off"
+                    autoCorrect="off"
                     spellCheck={false}
                 />
             </div>
diff --git a/src/graph/GraphViewerEngine.ts b/src/graph/GraphViewerEngine.ts
index 6b5692e..0fbeb94 100644
--- a/src/graph/GraphViewerEngine.ts
+++ b/src/graph/GraphViewerEngine.ts
@@ -18,6 +18,8 @@ import {
     WebColaEngine,
     ForceDirectedEngine,
 } from "./simulation";
+// TEMPORARY: Position persistence until backend storage exists (remove this line to disable)
+import { PositionPersistenceManager } from "./simulation/PositionPersistenceManager";
 import {
     NavigationEngine,
     NavigationState,
@@ -78,6 +80,9 @@ export class GraphViewerEngine extends AbstractGraphViewerEngine {
     private currentSimulationMode: SimulationMode;
     private storeUnsubscribe: (() => void) | null = null;
 
+    // TEMPORARY: Position persistence manager (remove this line to disable)
+    private positionPersistence: PositionPersistenceManager;
+
     constructor(
         container: HTMLDivElement,
         getCursor: () => string | null,
@@ -102,7 +107,14 @@ export class GraphViewerEngine extends AbstractGraphViewerEngine {
 
         // Subsystems
         this.renderer = new SVGRenderer(this.svg);
-        
+
+        // TEMPORARY: Initialize position persistence and load saved positions
+        this.positionPersistence = new PositionPersistenceManager();
+        const savedPositions = this.positionPersistence.loadPositions();
+        if (Object.keys(savedPositions).length > 0) {
+            this.simulationState = { positions: savedPositions };
+        }
+
         // Initialize simulation engine based on store mode
         this.currentSimulationMode = useTodoStore.getState().simulationMode;
         this.simulationEngine = this.createSimulationEngine(this.currentSimulationMode);
@@ -139,6 +151,9 @@ export class GraphViewerEngine extends AbstractGraphViewerEngine {
         });
         this.inputHandler.setCallback((event) => this.interactionController.handleEvent(event));
 
+        // TEMPORARY: Start position persistence monitoring
+        this.positionPersistence.start(() => this.simulationState);
+
         this.lastFrameTime = performance.now();
         this.startLoop();
     }
@@ -346,6 +361,8 @@ export class GraphViewerEngine extends AbstractGraphViewerEngine {
             cancelAnimationFrame(this.animationFrameId);
             this.animationFrameId = null;
         }
+        // TEMPORARY: Stop position persistence monitoring
+        this.positionPersistence.stop();
         this.storeUnsubscribe?.();
         this.storeUnsubscribe = null;
         this.inputHandler.destroy();
diff --git a/src/graph/NodeDetailOverlay.tsx b/src/graph/NodeDetailOverlay.tsx
index d93e12f..a12d939 100644
--- a/src/graph/NodeDetailOverlay.tsx
+++ b/src/graph/NodeDetailOverlay.tsx
@@ -2,11 +2,14 @@ import { useState, useEffect, useCallback } from "react";
 import { useTodoStore } from "../stores/todoStore";
 import { formatDistanceToNow } from "date-fns";
 import { getUrgencyColorCSSFromTimestamp } from "../utils/urgencyColor";
+import * as chrono from "chrono-node";
 
 interface EditState {
     field: 'id' | 'text' | 'due' | null;
     value: string;
-    timeValue?: string; // Optional time for due date editing
+    parsedDate?: Date | null; // Parsed date from natural language or picker
+    parseError?: string; // Error message if parsing fails
+    showPicker?: boolean; // Whether to show the date picker
 }
 
 export function NodeDetailOverlay() {
@@ -16,20 +19,11 @@ export function NodeDetailOverlay() {
 
     const task = cursor && graphData?.tasks[cursor] ? graphData.tasks[cursor] : null;
 
-    // Compute if task is blocked (any dependency not calculatedCompleted)
-    const isBlocked = (() => {
-        if (!task || !graphData) return false;
-        const childDepIds = task.children || [];
-        const deps = graphData.dependencies || {};
-        const tasks = graphData.tasks || {};
-        for (const depId of childDepIds) {
-            const dep = deps[depId];
-            if (!dep) continue;
-            const depTask = tasks[dep.toId];
-            if (depTask && !depTask.calculatedCompleted) return true;
-        }
-        return false;
-    })();
+    // Debug: log task data
+    // Current task loaded
+
+    // Backend provides depsClear - no need to calculate manually
+    const isBlocked = task ? (task.depsClear === false) : false;
 
     const [edit, setEdit] = useState<EditState>({ field: null, value: '' });
 
@@ -38,8 +32,19 @@ export function NodeDetailOverlay() {
         setEdit({ field: null, value: '' });
     }, [cursor]);
 
-    const startEdit = (field: EditState['field'], currentValue: string, timeValue?: string) => {
-        setEdit({ field, value: currentValue, timeValue });
+    const startEdit = (field: EditState['field'], currentValue: string) => {
+        if (field === 'due') {
+            // For due date, start with empty natural language input
+            setEdit({
+                field,
+                value: '',
+                parsedDate: currentValue ? new Date(parseInt(currentValue) * 1000) : null,
+                parseError: undefined,
+                showPicker: false
+            });
+        } else {
+            setEdit({ field, value: currentValue });
+        }
     };
 
     const cancelEdit = () => {
@@ -62,16 +67,13 @@ export function NodeDetailOverlay() {
                 if (edit.field === 'text') {
                     update.text = edit.value;
                 } else if (edit.field === 'due') {
-                    if (edit.value) {
-                        // Combine date + time (default to 23:59 if no time)
-                        const time = edit.timeValue || '23:59';
-                        const dateStr = `${edit.value}T${time}`;
-                        update.due = Math.floor(new Date(dateStr).getTime() / 1000);
+                    if (edit.parsedDate) {
+                        update.due = Math.floor(edit.parsedDate.getTime() / 1000);
                     } else {
                         update.due = null;
                     }
                 }
-                await api.setTaskApiTasksTaskIdPatch({ taskId: task.id, taskUpdate: update });
+                await api.setTaskApiTasksTaskIdPatch({ taskId: task.id, nodeUpdate: update });
             }
             setEdit({ field: null, value: '' });
         } catch (err) {
@@ -79,40 +81,62 @@ export function NodeDetailOverlay() {
         }
     };
 
+    const tryParseNaturalLanguage = () => {
+        if (!edit.value.trim()) {
+            setEdit({ ...edit, parsedDate: null, parseError: undefined });
+            return;
+        }
+
+        const parsed = chrono.parseDate(edit.value);
+        if (parsed) {
+            setEdit({ ...edit, parsedDate: parsed, parseError: undefined });
+        } else {
+            setEdit({ ...edit, parsedDate: null, parseError: 'Could not parse date. Try "tomorrow", "in 2 hours", "next monday at 3pm", or use the calendar.' });
+        }
+    };
+
     const handleKeyDown = (e: React.KeyboardEvent) => {
         if (e.key === 'Enter') {
             e.preventDefault();
-            saveEdit();
+            if (edit.field === 'due') {
+                tryParseNaturalLanguage();
+                // Only save if we have a parsed date or if clearing
+                if (edit.parsedDate || !edit.value.trim()) {
+                    saveEdit();
+                }
+            } else {
+                saveEdit();
+            }
         } else if (e.key === 'Escape') {
             e.preventDefault();
             cancelEdit();
         }
     };
 
-    // Space to toggle completion (disabled for inferred or blocked nodes)
-    const canToggle = task && !task.inferred && !isBlocked;
-    
+    // Space to toggle completion (disabled for gates or blocked nodes)
+    const canToggle = task && task.nodeType === "Task" && !isBlocked;
+
     const toggleCompletion = useCallback(async () => {
-        if (!task || !api || task.inferred || isBlocked) return;
+        if (!task || !api || task.nodeType !== "Task" || isBlocked) return;
         try {
             await api.setTaskApiTasksTaskIdPatch({
                 taskId: task.id,
-                taskUpdate: { completed: !task.completed },
+                nodeUpdate: { completed: !task.completed },
             });
         } catch (err) {
             console.error("Failed to toggle completion:", err);
         }
     }, [task, api, isBlocked]);
 
-    const toggleInferred = useCallback(async () => {
+    const setNodeType = useCallback(async (newType: string) => {
         if (!task || !api) return;
         try {
             await api.setTaskApiTasksTaskIdPatch({
                 taskId: task.id,
-                taskUpdate: { inferred: !task.inferred },
+                nodeUpdate: { nodeType: newType },
             });
         } catch (err) {
-            console.error("Failed to toggle inferred:", err);
+            console.error("Failed to change node type:", err);
         }
     }, [task, api]);
 
@@ -156,7 +180,7 @@ export function NodeDetailOverlay() {
     const clearDue = async () => {
         if (!api || !task) return;
         try {
-            await api.setTaskApiTasksTaskIdPatch({ taskId: task.id, taskUpdate: { due: null } });
+            await api.setTaskApiTasksTaskIdPatch({ taskId: task.id, nodeUpdate: { due: null } });
             setEdit({ field: null, value: '' });
         } catch (err) {
             console.error("Failed to clear due date:", err);
@@ -218,14 +242,20 @@ export function NodeDetailOverlay() {
             </div>
 
             {/* Status line */}
-            <div className="flex gap-4 text-xs">
-                {/* Node type: task or inferred - click to toggle */}
-                <span
-                    onClick={toggleInferred}
-                    className="cursor-pointer text-white/50 hover:text-white/70"
+            <div className="flex gap-4 text-xs items-center">
+                {/* Node type selector */}
+                <select
+                    value={task.nodeType || "Task"}
+                    onChange={(e) => setNodeType(e.target.value)}
+                    className="bg-white/10 text-white hover:text-white border border-white/20 rounded px-2 py-1 cursor-pointer text-xs"
+                    style={{ color: 'white' }}
                 >
-                    {task.inferred ? "inferred" : "task"}
-                </span>
+                    <option value="Task" style={{ backgroundColor: '#1f2937', color: 'white' }}>task</option>
+                    <option value="And" style={{ backgroundColor: '#1f2937', color: 'white' }}>and (all)</option>
+                    <option value="Or" style={{ backgroundColor: '#1f2937', color: 'white' }}>or (any)</option>
+                    <option value="Not" style={{ backgroundColor: '#1f2937', color: 'white' }}>not (none)</option>
+                    <option value="ExactlyOne" style={{ backgroundColor: '#1f2937', color: 'white' }}>xor (one)</option>
+                </select>
 
                 {/* Status: blocked > completed > actionable */}
                 {isBlocked ? (
@@ -234,47 +264,115 @@ export function NodeDetailOverlay() {
                     <span
                         onClick={() => canToggle && toggleCompletion()}
                         className={
-                            task.inferred
+                            task.nodeType !== "Task"
                                 ? "text-white/30"
-                                : task.calculatedCompleted
+                                : task.calculatedValue
                                     ? "text-green-400 cursor-pointer hover:text-green-300"
                                     : "text-orange-400 cursor-pointer hover:text-orange-300"
                         }
                     >
-                        {task.calculatedCompleted ? "completed" : "actionable"}
+                        {task.calculatedValue ? "completed" : "actionable"}
                     </span>
                 )}
 
                 {/* Due - displays calculatedDue (inferred), edits task.due (own) */}
                 {isEditing('due') ? (
-                    <div className="flex items-center gap-2">
-                        <input
-                            type="date"
-                            value={edit.value as string}
-                            onChange={(e) => setEdit({ ...edit, value: e.target.value })}
-                            onKeyDown={handleKeyDown}
-                            autoFocus
-                            className="bg-white/10 border border-white/30 rounded px-1 py-0.5 text-white text-base outline-none"
-                        />
-                        <input
-                            type="time"
-                            value={edit.timeValue || ''}
-                            onChange={(e) => setEdit({ ...edit, timeValue: e.target.value })}
-                            onKeyDown={handleKeyDown}
-                            placeholder="23:59"
-                            className="bg-white/10 border border-white/30 rounded px-1 py-0.5 text-white text-base outline-none w-20"
-                        />
-                        <button onClick={saveEdit} className="text-green-400 hover:text-green-300">save</button>
-                        <button onClick={clearDue} className="text-red-400 hover:text-red-300">clear</button>
-                        <button onClick={cancelEdit} className="text-white/40 hover:text-white/60">cancel</button>
+                    <div className="flex flex-col gap-1">
+                        <div className="flex items-center gap-2">
+                            {!edit.showPicker ? (
+                                <>
+                                    <input
+                                        type="text"
+                                        value={edit.value}
+                                        onChange={(e) => setEdit({ ...edit, value: e.target.value, parseError: undefined })}
+                                        onKeyDown={handleKeyDown}
+                                        onBlur={tryParseNaturalLanguage}
+                                        autoFocus
+                                        className="bg-white/10 border border-white/30 rounded px-2 py-0.5 text-white text-base outline-none flex-1"
+                                    />
+                                    <button
+                                        onClick={() => setEdit({ ...edit, showPicker: true })}
+                                        className="text-white hover:text-white/80 px-2"
+                                        title="Open calendar"
+                                    >
+                                        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
+                                            <rect x="2" y="3" width="12" height="11" rx="1" stroke="currentColor" strokeWidth="1.5"/>
+                                            <line x1="2" y1="6" x2="14" y2="6" stroke="currentColor" strokeWidth="1.5"/>
+                                            <line x1="5" y1="1" x2="5" y2="4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/>
+                                            <line x1="11" y1="1" x2="11" y2="4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/>
+                                        </svg>
+                                    </button>
+                                </>
+                            ) : (
+                                <>
+                                    <input
+                                        type="date"
+                                        value={edit.parsedDate ? edit.parsedDate.toISOString().slice(0, 10) : ''}
+                                        onChange={(e) => {
+                                            const newDate = e.target.value ? new Date(e.target.value) : null;
+                                            // Preserve time if it exists
+                                            if (newDate && edit.parsedDate) {
+                                                newDate.setHours(edit.parsedDate.getHours(), edit.parsedDate.getMinutes());
+                                            }
+                                            setEdit({ ...edit, parsedDate: newDate, parseError: undefined });
+                                        }}
+                                        onKeyDown={handleKeyDown}
+                                        autoFocus
+                                        className="bg-white/10 border border-white/30 rounded px-1 py-0.5 text-white text-base outline-none"
+                                    />
+                                    <input
+                                        type="time"
+                                        value={edit.parsedDate ? edit.parsedDate.toTimeString().slice(0, 5) : ''}
+                                        onChange={(e) => {
+                                            if (edit.parsedDate && e.target.value) {
+                                                const [hours, minutes] = e.target.value.split(':').map(Number);
+                                                const newDate = new Date(edit.parsedDate);
+                                                newDate.setHours(hours, minutes);
+                                                setEdit({ ...edit, parsedDate: newDate, parseError: undefined });
+                                            }
+                                        }}
+                                        onKeyDown={handleKeyDown}
+                                        className="bg-white/10 border border-white/30 rounded px-1 py-0.5 text-white text-base outline-none w-20"
+                                    />
+                                    <button
+                                        onClick={() => setEdit({ ...edit, showPicker: false })}
+                                        className="text-white/60 hover:text-white/80 text-xs"
+                                        title="Back to text input"
+                                    >
+                                        text
+                                    </button>
+                                </>
+                            )}
+                        </div>
+                        {edit.parsedDate && !edit.showPicker && (
+                            <div className="text-green-400 text-xs">
+                                → {edit.parsedDate.toLocaleString()}
+                            </div>
+                        )}
+                        {edit.parseError && (
+                            <div className="text-red-400 text-xs">
+                                {edit.parseError}
+                            </div>
+                        )}
+                        <div className="flex items-center gap-2">
+                            <button
+                                onClick={saveEdit}
+                                disabled={edit.field === 'due' && edit.value.trim() !== '' && !edit.parsedDate}
+                                className="text-green-400 hover:text-green-300 disabled:text-gray-500 disabled:cursor-not-allowed"
+                            >
+                                save
+                            </button>
+                            <button onClick={clearDue} className="text-red-400 hover:text-red-300">clear</button>
+                            <button onClick={cancelEdit} className="text-white/40 hover:text-white/60">cancel</button>
+                        </div>
                     </div>
                 ) : (
                     <span
-                        onClick={() => startEdit('due', formatDueDateForInput(task.due), formatDueTimeForInput(task.due))}
+                        onClick={() => startEdit('due', task.due?.toString() || '')}
                         className="cursor-pointer hover:opacity-80"
                         style={task.calculatedDue && !task.calculatedCompleted ? { color: getUrgencyColorCSSFromTimestamp(task.calculatedDue) } : undefined}
                     >
-                        due: {task.calculatedDue 
+                        due: {task.calculatedDue
                             ? `${formatDateRelative(task.calculatedDue)} / ${formatDateAbsolute(task.calculatedDue)}`
                             : "-"}
                     </span>
diff --git a/src/graph/preprocess/pipeline.ts b/src/graph/preprocess/pipeline.ts
index dadae55..5b03d4b 100644
--- a/src/graph/preprocess/pipeline.ts
+++ b/src/graph/preprocess/pipeline.ts
@@ -2,7 +2,7 @@
  * Graph preprocessing pipeline: raw API data → styled graph ready for rendering.
  */
 
-import { TaskListOut } from "todo-client";
+import { NodeListOut } from "todo-client";
 import { nestGraphData, NestedGraphData } from "./nestGraphData";
 import { computeConnectedComponents, ComponentGraphData } from "./connectedComponents";
 import { baseStyleGraphData, conditionalStyleGraphData, StyledGraphData } from "./styleGraphData";
@@ -13,7 +13,7 @@ export type ProcessedGraphData = StyledGraphData<ComponentGraphData<NestedGraphD
 /**
  * Transform raw API task list into styled graph data ready for simulation.
  */
-export function preprocessGraph(taskList: TaskListOut): ProcessedGraphData {
+export function preprocessGraph(taskList: NodeListOut): ProcessedGraphData {
     const nested = nestGraphData(taskList);
     const withComponents = computeConnectedComponents(nested);
     const styled = baseStyleGraphData(withComponents);
diff --git a/src/graph/preprocess/styleGraphData.ts b/src/graph/preprocess/styleGraphData.ts
index 0d3a1cb..b2a4cbe 100644
--- a/src/graph/preprocess/styleGraphData.ts
+++ b/src/graph/preprocess/styleGraphData.ts
@@ -196,58 +196,55 @@ export function baseStyleGraphData<G extends NestedGraphData>(graphData: G): Sty
     } as StyledGraphData<G>;
 }
 
-/** Apply conditional styling based on node state (e.g., completed, actionable, inferred). */
+/** Apply conditional styling based on node state (e.g., completed, actionable, node type). */
 export function conditionalStyleGraphData<G extends StyledGraphData<NestedGraphData>>(graphData: G): G {
-    // Build a lookup for task calculatedCompleted status
-    const taskCalcCompleted = new Map<string, boolean>();
-    for (const [tid, t] of Object.entries(graphData.tasks)) {
-        const d = t.data as { calculatedCompleted?: boolean };
-        taskCalcCompleted.set(tid, d.calculatedCompleted === true);
-    }
-
     return {
         ...graphData,
         tasks: Object.fromEntries(
             Object.entries(graphData.tasks).map(([taskId, task]) => {
-                const data = task.data as { calculatedCompleted?: boolean; depsClear?: boolean; inferred?: boolean; completed?: boolean; children?: string[]; calculatedDue?: number | null };
-                const isInferred = data.inferred;
+                const data = task.data as {
+                    nodeType?: string;
+                    calculatedValue?: boolean;
+                    depsClear?: boolean;
+                    isActionable?: boolean;
+                    calculatedDue?: number | null;
+                };
+
+                // Node type determines shape
+                const nodeType = data.nodeType || "Task";
+                const shapeMap: Record<string, NodeShape> = {
+                    'Task': 'square',
+                    'And': 'upTriangle',
+                    'Or': 'downTriangle',
+                    'Not': 'triangleCircle',
+                    'ExactlyOne': 'circle'
+                };
+                const shape: NodeShape = shapeMap[nodeType] || 'square';
 
-                // Check if blocked: any direct dependency not calculatedCompleted
-                // children = dependency IDs where this task is fromId (things this depends on)
-                const childDepIds = data.children || [];
-                const childTaskIds = childDepIds
-                    .map(depId => (graphData.dependencies[depId]?.data as { toId?: string })?.toId)
-                    .filter((id): id is string => id != null);
-                
-                // Blocked if any dependency is not calculatedCompleted
-                const isBlocked = childTaskIds.length > 0 && childTaskIds.some(id => !taskCalcCompleted.get(id));
-                
-                // If blocked, ignore completed status - just show as blocked
-                // Only check completion when deps are clear
-                const isCompleted = !isBlocked && data.calculatedCompleted;
-                const isActionable = !isBlocked && !isCompleted;
+                // Backend provides all calculated properties
+                const isBlocked = data.depsClear === false;
+                const isCompleted = data.calculatedValue === true;
+                const isActionable = data.isActionable === true;
 
-                // Shape: upward triangle for inferred (AND gate), square for regular
-                const shape: NodeShape = isInferred ? 'upTriangle' : 'square';
-                // Hollow: incomplete/blocked = hollow (background fill), complete = solid (color fill)
+                // Hollow: incomplete = hollow (background fill), complete = solid (color fill)
                 const hollow = !isCompleted;
 
-                // Label color: urgency-based if has due date and not calculatedCompleted, else white
+                // Label color: urgency-based if has due date and not completed, else white
                 let labelColor: Color = [1, 1, 1];
-                if (data.calculatedDue && !data.calculatedCompleted) {
+                if (data.calculatedDue && !isCompleted) {
                     labelColor = getUrgencyColorFromTimestamp(data.calculatedDue);
                 }
 
                 let styledTask = { ...task, shape, hollow, labelColor };
 
                 if (isBlocked) {
-                    // Blocked: dim the node, ignore its own completed status
+                    // Blocked: dim the node
                     return [taskId, { ...styledTask, brightnessMultiplier: 0.1 }];
                 }
                 if (isCompleted) {
                     return [taskId, { ...styledTask, text: styledTask.text }];
                 }
-                // Actionable: deps clear, not completed
+                // Actionable or other states
                 return [taskId, styledTask];
             })
         ),
diff --git a/src/graph/render/SVGRenderer.ts b/src/graph/render/SVGRenderer.ts
index 69af173..ef2cad4 100644
--- a/src/graph/render/SVGRenderer.ts
+++ b/src/graph/render/SVGRenderer.ts
@@ -270,18 +270,41 @@ export class SVGRenderer {
         let pathD: string;
         if (node.shape === 'upTriangle') {
             // Upright equilateral triangle (AND gate)
-            // Height of equilateral triangle: h = side * sqrt(3) / 2
-            // We want it to fit in the same bounding box as the square
             const side = size;
             const h = side * Math.sqrt(3) / 2;
-            // Center the triangle vertically
             const topY = y - h / 2;
             const bottomY = y + h / 2;
             const leftX = x - side / 2;
             const rightX = x + side / 2;
             pathD = `M ${x} ${topY} L ${rightX} ${bottomY} L ${leftX} ${bottomY} Z`;
+        } else if (node.shape === 'downTriangle') {
+            // Inverted equilateral triangle (OR gate)
+            const side = size;
+            const h = side * Math.sqrt(3) / 2;
+            const topY = y - h / 2;
+            const bottomY = y + h / 2;
+            const leftX = x - side / 2;
+            const rightX = x + side / 2;
+            // Flip: bottom vertex at top, top vertices at bottom
+            pathD = `M ${x} ${bottomY} L ${rightX} ${topY} L ${leftX} ${topY} Z`;
+        } else if (node.shape === 'circle') {
+            // Circle (ExactlyOne gate)
+            const radius = halfSize;
+            // Use SVG arc commands to draw a circle
+            pathD = `M ${x - radius} ${y} A ${radius} ${radius} 0 1 0 ${x + radius} ${y} A ${radius} ${radius} 0 1 0 ${x - radius} ${y} Z`;
+        } else if (node.shape === 'triangleCircle') {
+            // Triangle with circle overlay (NOT gate)
+            const side = size;
+            const h = side * Math.sqrt(3) / 2;
+            const topY = y - h / 2;
+            const bottomY = y + h / 2;
+            const leftX = x - side / 2;
+            const rightX = x + side / 2;
+            const radius = halfSize * 0.6;
+            // Draw upTriangle, then add circle in the same path
+            pathD = `M ${x} ${topY} L ${rightX} ${bottomY} L ${leftX} ${bottomY} Z M ${x - radius} ${y} A ${radius} ${radius} 0 1 0 ${x + radius} ${y} A ${radius} ${radius} 0 1 0 ${x - radius} ${y} Z`;
         } else {
-            // Square
+            // Square (default for Task nodes)
             const left = x - halfSize;
             const right = x + halfSize;
             const top = y - halfSize;
diff --git a/src/graph/render/utils.ts b/src/graph/render/utils.ts
index 629e752..72b623b 100644
--- a/src/graph/render/utils.ts
+++ b/src/graph/render/utils.ts
@@ -19,7 +19,7 @@ export interface ViewTransform {
 export type Color = [number, number, number];
 export type Vec2 = [number, number];
 
-export type NodeShape = 'square' | 'upTriangle';
+export type NodeShape = 'square' | 'upTriangle' | 'downTriangle' | 'circle' | 'triangleCircle';
 
 export interface RenderNode {
     data: { id: string };
diff --git a/src/graph/simulation/PositionPersistenceManager.ts b/src/graph/simulation/PositionPersistenceManager.ts
new file mode 100644
index 0000000..9669dbb
--- /dev/null
+++ b/src/graph/simulation/PositionPersistenceManager.ts
@@ -0,0 +1,285 @@
+/**
+ * ===================================================================
+ * TEMPORARY SOLUTION - Position Persistence Manager
+ * ===================================================================
+ *
+ * This is a TEMPORARY workaround to persist node positions between
+ * sessions while we work on a proper backend storage solution.
+ *
+ * REMOVAL PLAN:
+ * When proper backend position storage is implemented, remove this
+ * entire file and delete the 2-3 lines that instantiate it in
+ * GraphViewerEngine.ts (search for "PositionPersistenceManager").
+ *
+ * DESIGN GOALS:
+ * - Zero dependencies on other graph systems
+ * - Self-contained with clear start/stop lifecycle
+ * - Trivial to remove (no scattered integration points)
+ *
+ * ===================================================================
+ */
+
+import { SimulationState, Position } from "./types";
+
+/**
+ * Configuration for the position persistence manager.
+ */
+export interface PositionPersistenceConfig {
+    /** How often to check positions (ms). Default: 1000 (1 second) */
+    pollInterval?: number;
+
+    /** Maximum movement threshold to consider "settled" (world space units). Default: 0.5 */
+    settlementThreshold?: number;
+
+    /** Debounce duration for saving to storage (ms). Default: 2000 (2 seconds) */
+    saveDebounce?: number;
+
+    /** LocalStorage key for persisted positions. Default: "graph-positions" */
+    storageKey?: string;
+}
+
+const DEFAULT_CONFIG: Required<PositionPersistenceConfig> = {
+    pollInterval: 1000,
+    settlementThreshold: 0.5,
+    saveDebounce: 2000,
+    storageKey: "graph-positions",
+};
+
+/**
+ * Manages automatic persistence of node positions to browser storage.
+ *
+ * Monitors simulation positions and saves them to localStorage when
+ * the graph settles (nodes stop moving). On initialization, loads
+ * saved positions to restore previous layout.
+ *
+ * TEMPORARY: This is a stopgap until backend position storage exists.
+ */
+export class PositionPersistenceManager {
+    private config: Required<PositionPersistenceConfig>;
+    private pollIntervalId: number | null = null;
+    private saveTimeoutId: number | null = null;
+
+    private lastPositions: Record<string, Position> | null = null;
+    private isCurrentlySettled = false;
+
+    /**
+     * Callback to get current simulation state.
+     * Provided by the host (GraphViewerEngine) to avoid tight coupling.
+     */
+    private getSimulationState: (() => SimulationState) | null = null;
+
+    constructor(config: PositionPersistenceConfig = {}) {
+        this.config = { ...DEFAULT_CONFIG, ...config };
+    }
+
+    /**
+     * Start monitoring positions for persistence.
+     *
+     * @param getSimulationState - Function to get current positions
+     */
+    start(getSimulationState: () => SimulationState): void {
+        if (this.pollIntervalId !== null) {
+            console.warn("[PositionPersistence] Already started, ignoring start()");
+            return;
+        }
+
+        this.getSimulationState = getSimulationState;
+        this.lastPositions = null;
+        this.isCurrentlySettled = false;
+
+        // Start polling
+        this.pollIntervalId = window.setInterval(
+            () => this.checkPositions(),
+            this.config.pollInterval
+        );
+
+        console.log("[PositionPersistence] Started monitoring");
+    }
+
+    /**
+     * Stop monitoring and clean up.
+     */
+    stop(): void {
+        if (this.pollIntervalId !== null) {
+            window.clearInterval(this.pollIntervalId);
+            this.pollIntervalId = null;
+        }
+
+        if (this.saveTimeoutId !== null) {
+            window.clearTimeout(this.saveTimeoutId);
+            this.saveTimeoutId = null;
+        }
+
+        this.getSimulationState = null;
+        this.lastPositions = null;
+        this.isCurrentlySettled = false;
+
+        console.log("[PositionPersistence] Stopped monitoring");
+    }
+
+    /**
+     * Load persisted positions from storage.
+     * Call this during initialization to restore previous layout.
+     *
+     * @returns Loaded positions, or empty object if none exist
+     */
+    loadPositions(): Record<string, Position> {
+        try {
+            const stored = localStorage.getItem(this.config.storageKey);
+            if (!stored) {
+                console.log("[PositionPersistence] No saved positions found");
+                return {};
+            }
+
+            const parsed = JSON.parse(stored) as Record<string, Position>;
+            const count = Object.keys(parsed).length;
+            console.log(`[PositionPersistence] Loaded ${count} node positions from storage`);
+            return parsed;
+        } catch (err) {
+            console.error("[PositionPersistence] Failed to load positions:", err);
+            return {};
+        }
+    }
+
+    /**
+     * Manually save current positions to storage.
+     * Normally called automatically when graph settles.
+     */
+    savePositionsNow(): void {
+        if (!this.getSimulationState) {
+            console.warn("[PositionPersistence] Cannot save, not started");
+            return;
+        }
+
+        const state = this.getSimulationState();
+        const positions = state.positions;
+
+        if (Object.keys(positions).length === 0) {
+            console.log("[PositionPersistence] No positions to save (empty graph)");
+            return;
+        }
+
+        try {
+            localStorage.setItem(this.config.storageKey, JSON.stringify(positions));
+            const count = Object.keys(positions).length;
+            console.log(`[PositionPersistence] Saved ${count} node positions to storage`);
+        } catch (err) {
+            console.error("[PositionPersistence] Failed to save positions:", err);
+        }
+    }
+
+    /**
+     * Clear persisted positions from storage.
+     */
+    clearPersistedPositions(): void {
+        try {
+            localStorage.removeItem(this.config.storageKey);
+            console.log("[PositionPersistence] Cleared persisted positions");
+        } catch (err) {
+            console.error("[PositionPersistence] Failed to clear positions:", err);
+        }
+    }
+
+    // ═══════════════════════════════════════════════════════════════════════════
+    // PRIVATE METHODS
+    // ═══════════════════════════════════════════════════════════════════════════
+
+    /**
+     * Poll current positions and check for settlement.
+     * Called by interval timer.
+     */
+    private checkPositions(): void {
+        if (!this.getSimulationState) return;
+
+        const state = this.getSimulationState();
+        const currentPositions = state.positions;
+
+        // Skip if no positions yet
+        if (Object.keys(currentPositions).length === 0) {
+            return;
+        }
+
+        // First poll - store baseline
+        if (this.lastPositions === null) {
+            this.lastPositions = { ...currentPositions };
+            return;
+        }
+
+        // Check if settled
+        const settled = this.isGraphSettled(this.lastPositions, currentPositions);
+
+        // Detect transition: unsettled → settled
+        if (!this.isCurrentlySettled && settled) {
+            console.log("[PositionPersistence] Graph settled, scheduling save...");
+            this.scheduleSave();
+        }
+
+        // Update state
+        this.isCurrentlySettled = settled;
+        this.lastPositions = { ...currentPositions };
+    }
+
+    /**
+     * Determine if graph has settled (all nodes below movement threshold).
+     *
+     * @param prev - Previous positions
+     * @param current - Current positions
+     * @returns true if all nodes have moved less than threshold
+     */
+    private isGraphSettled(
+        prev: Record<string, Position>,
+        current: Record<string, Position>
+    ): boolean {
+        const threshold = this.config.settlementThreshold;
+
+        // Check all nodes that exist in both snapshots
+        for (const nodeId in current) {
+            if (!(nodeId in prev)) {
+                // New node appeared - not settled
+                return false;
+            }
+
+            const prevPos = prev[nodeId];
+            const currPos = current[nodeId];
+
+            const dx = currPos.x - prevPos.x;
+            const dy = currPos.y - prevPos.y;
+            const distance = Math.sqrt(dx * dx + dy * dy);
+
+            if (distance > threshold) {
+                // This node moved too much - not settled
+                return false;
+            }
+        }
+
+        // Check if any nodes were removed
+        for (const nodeId in prev) {
+            if (!(nodeId in current)) {
+                // Node disappeared - not settled
+                return false;
+            }
+        }
+
+        return true;
+    }
+
+    /**
+     * Schedule a debounced save to storage.
+     * Multiple calls within debounce window will reset the timer.
+     */
+    private scheduleSave(): void {
+        // Clear existing timeout
+        if (this.saveTimeoutId !== null) {
+            window.clearTimeout(this.saveTimeoutId);
+        }
+
+        // Schedule new save
+        this.saveTimeoutId = window.setTimeout(
+            () => {
+                this.savePositionsNow();
+                this.saveTimeoutId = null;
+            },
+            this.config.saveDebounce
+        );
+    }
+}
diff --git a/src/graph/simulation/REMOVE_EDGE_CROSSING_DETECTOR.md b/src/graph/simulation/REMOVE_EDGE_CROSSING_DETECTOR.md
new file mode 100644
index 0000000..5cc51a4
--- /dev/null
+++ b/src/graph/simulation/REMOVE_EDGE_CROSSING_DETECTOR.md
@@ -0,0 +1,102 @@
+# Removing Edge Crossing Detector (Modular Feature)
+
+## What This Does
+
+Detects edge crossings in saved layouts to determine if they should be preserved or re-computed. If saved positions have few edge crossings (good layout), WebCola skips the unconstrained settling phase and preserves them. If many crossings (poor layout), it does a full two-phase re-layout.
+
+## When to Remove
+
+- If you want WebCola to always do two-phase initialization (unconstrained → constrained)
+- If edge crossing detection is too expensive for your use case
+- If you prefer simpler logic (always re-layout on first load)
+
+## How to Remove (2 steps)
+
+### Step 1: Delete the detector file
+
+```bash
+rm src/graph/simulation/edgeCrossingDetector.ts
+rm src/graph/simulation/REMOVE_EDGE_CROSSING_DETECTOR.md  # This file
+```
+
+### Step 2: Remove integration from webColaEngine.ts
+
+Search for `MODULAR` comments and delete marked sections:
+
+**Delete import:**
+```typescript
+// DELETE THIS LINE:
+import { hasGoodLayout } from "../edgeCrossingDetector";
+```
+
+**Replace the if block (around line 288):**
+
+**BEFORE (with edge crossing detection):**
+```typescript
+if (isFirstInit) {
+    // MODULAR: Check if saved positions are high quality (few edge crossings)
+    // DELETE these 5 lines to always use two-phase init:
+    const edges = Object.values(graph.dependencies).map(dep => ({
+        fromId: dep.data.fromId,
+        toId: dep.data.toId
+    }));
+    const hasGoodSavedLayout = hasGoodLayout(prevState.positions, edges);
+
+    if (hasGoodSavedLayout) {
+        // Saved positions are good quality - skip unconstrained phase
+        console.log("[WebCola] Preserved saved positions (good layout detected)");
+        this.constraintsApplied = true;
+        this.lastMutationTime = null;
+        this.rebuildLayout(true);
+    } else {
+        // Saved positions are poor quality or missing - do two-phase init
+        console.log("[WebCola] Starting two-phase init (edge crossings detected or no saved positions)");
+        this.lastMutationTime = performance.now();
+        this.constraintsApplied = false;
+        this.rebuildLayout(false);
+    }
+}
+```
+
+**AFTER (always two-phase init):**
+```typescript
+if (isFirstInit) {
+    // First initialization: start without constraints, apply after delay
+    this.lastMutationTime = performance.now();
+    this.constraintsApplied = false;
+    this.rebuildLayout(false);
+}
+```
+
+## Configuration (Before Removal)
+
+If you want to adjust thresholds instead of removing:
+
+**Option 1: Make it more strict (preserve fewer layouts)**
+```typescript
+const hasGoodSavedLayout = hasGoodLayout(prevState.positions, edges, {
+    threshold: 0.02  // Only preserve if < 2% edge crossings (stricter)
+});
+```
+
+**Option 2: Make it more lenient (preserve more layouts)**
+```typescript
+const hasGoodSavedLayout = hasGoodLayout(prevState.positions, edges, {
+    threshold: 0.10  // Preserve even with 10% edge crossings (looser)
+});
+```
+
+**Option 3: Adjust sampling for large graphs**
+```typescript
+const hasGoodSavedLayout = hasGoodLayout(prevState.positions, edges, {
+    samplingThreshold: 200,  // Use sampling only for >200 edges
+    sampleSize: 500          // Check 500 samples instead of 200
+});
+```
+
+## Testing After Removal
+
+1. Clear localStorage: `localStorage.removeItem('graph-positions')`
+2. Load a graph and let it settle
+3. Reload page
+4. Positions should now always do two-phase init (positions will shift during first second)
diff --git a/src/graph/simulation/REMOVE_POSITION_PERSISTENCE.md b/src/graph/simulation/REMOVE_POSITION_PERSISTENCE.md
new file mode 100644
index 0000000..e74d267
--- /dev/null
+++ b/src/graph/simulation/REMOVE_POSITION_PERSISTENCE.md
@@ -0,0 +1,58 @@
+# Removing Position Persistence (Temporary Feature)
+
+## Why This Exists
+
+This is a **temporary client-side solution** to persist node positions between browser sessions. It stores positions in `localStorage` and restores them on page load.
+
+**This should be removed** once proper backend position storage is implemented.
+
+## How to Remove (2 steps)
+
+### Step 1: Delete the persistence file
+
+```bash
+rm src/graph/simulation/PositionPersistenceManager.ts
+rm src/graph/simulation/REMOVE_POSITION_PERSISTENCE.md  # This file
+```
+
+### Step 2: Remove integration from GraphViewerEngine.ts
+
+Search for `TEMPORARY` comments and delete the marked lines:
+
+```typescript
+// DELETE THIS IMPORT:
+import { PositionPersistenceManager } from "./simulation/PositionPersistenceManager";
+
+// DELETE THIS FIELD:
+private positionPersistence: PositionPersistenceManager;
+
+// DELETE THIS BLOCK (3 lines):
+this.positionPersistence = new PositionPersistenceManager();
+const savedPositions = this.positionPersistence.loadPositions();
+if (Object.keys(savedPositions).length > 0) {
+    this.simulationState = { positions: savedPositions };
+}
+
+// DELETE THIS LINE:
+this.positionPersistence.start(() => this.simulationState);
+
+// DELETE THIS LINE:
+this.positionPersistence.stop();
+```
+
+### Step 3: Remove export from simulation/index.ts
+
+```typescript
+// DELETE THIS EXPORT:
+export * from "./PositionPersistenceManager";
+```
+
+## That's It!
+
+The feature is completely removed with no orphaned code.
+
+## Testing After Removal
+
+1. Clear localStorage: `localStorage.removeItem('graph-positions')`
+2. Reload page - positions should now be computed fresh each time
+3. Backend position storage should handle persistence instead
diff --git a/src/graph/simulation/edgeCrossingDetector.ts b/src/graph/simulation/edgeCrossingDetector.ts
new file mode 100644
index 0000000..c436fee
--- /dev/null
+++ b/src/graph/simulation/edgeCrossingDetector.ts
@@ -0,0 +1,263 @@
+/**
+ * ===================================================================
+ * MODULAR UTILITY - Edge Crossing Detection
+ * ===================================================================
+ *
+ * Detects edge crossings in a graph layout to assess layout quality.
+ * Used to determine whether saved positions should be preserved or
+ * whether a full layout re-computation is needed.
+ *
+ * REMOVAL:
+ * Delete this file and remove the import + 1 function call in
+ * webColaEngine.ts (search for "edgeCrossingDetector").
+ *
+ * ===================================================================
+ */
+
+import { Position } from "./types";
+
+/**
+ * Edge representation for crossing detection.
+ */
+export interface EdgeForCrossing {
+    fromId: string;
+    toId: string;
+}
+
+/**
+ * Configuration for edge crossing detection.
+ */
+export interface EdgeCrossingConfig {
+    /**
+     * Threshold for determining "good" layout (ratio of crossings).
+     * Default: 0.05 (5% of edge pairs can cross)
+     */
+    threshold?: number;
+
+    /**
+     * For large graphs, use sampling instead of checking all pairs.
+     * Default: 100 edges (if graph has more, use sampling)
+     */
+    samplingThreshold?: number;
+
+    /**
+     * Number of samples to check when sampling.
+     * Default: 200
+     */
+    sampleSize?: number;
+}
+
+const DEFAULT_CONFIG: Required<EdgeCrossingConfig> = {
+    threshold: 0.05,
+    samplingThreshold: 100,
+    sampleSize: 200,
+};
+
+/**
+ * Main API: Check if a layout has good quality (few edge crossings).
+ *
+ * @param positions - Node positions in world space
+ * @param edges - Graph edges
+ * @param config - Optional configuration
+ * @returns true if crossing ratio is below threshold (good layout)
+ */
+export function hasGoodLayout(
+    positions: Record<string, Position>,
+    edges: EdgeForCrossing[],
+    config: EdgeCrossingConfig = {}
+): boolean {
+    const cfg = { ...DEFAULT_CONFIG, ...config };
+
+    if (edges.length < 2) {
+        // Trivial graph - no crossings possible
+        return true;
+    }
+
+    // Choose strategy based on graph size
+    let crossingRatio: number;
+    if (edges.length <= cfg.samplingThreshold) {
+        // Small graph - check all pairs precisely
+        crossingRatio = calculateExactCrossingRatio(positions, edges);
+    } else {
+        // Large graph - use sampling for speed
+        crossingRatio = estimateCrossingRatio(positions, edges, cfg.sampleSize);
+    }
+
+    return crossingRatio < cfg.threshold;
+}
+
+// ═══════════════════════════════════════════════════════════════════════════
+// EXACT CROSSING DETECTION (for small graphs)
+// ═══════════════════════════════════════════════════════════════════════════
+
+/**
+ * Calculate exact crossing ratio by checking all edge pairs.
+ * Optimized with bounding box pre-check for fast rejection.
+ *
+ * Complexity: O(E²) worst case, but typically much faster due to rejection.
+ */
+function calculateExactCrossingRatio(
+    positions: Record<string, Position>,
+    edges: EdgeForCrossing[]
+): number {
+    let crossings = 0;
+    let validPairs = 0;
+
+    // Check all distinct pairs of edges
+    for (let i = 0; i < edges.length; i++) {
+        for (let j = i + 1; j < edges.length; j++) {
+            const e1 = edges[i];
+            const e2 = edges[j];
+
+            // Skip if edges share a node (they touch at endpoint, not a crossing)
+            if (edgesShareNode(e1, e2)) continue;
+
+            // Get positions (skip if any missing)
+            const p1 = positions[e1.fromId];
+            const p2 = positions[e1.toId];
+            const p3 = positions[e2.fromId];
+            const p4 = positions[e2.toId];
+            if (!p1 || !p2 || !p3 || !p4) continue;
+
+            validPairs++;
+
+            // Fast bounding box rejection (eliminates ~90% of pairs)
+            if (!boundingBoxesOverlap(p1, p2, p3, p4)) continue;
+
+            // Expensive line segment intersection test
+            if (segmentsIntersect(p1, p2, p3, p4)) {
+                crossings++;
+            }
+        }
+    }
+
+    return validPairs > 0 ? crossings / validPairs : 0;
+}
+
+// ═══════════════════════════════════════════════════════════════════════════
+// SAMPLED CROSSING DETECTION (for large graphs)
+// ═══════════════════════════════════════════════════════════════════════════
+
+/**
+ * Estimate crossing ratio by sampling random edge pairs.
+ * Much faster for large graphs, with small accuracy trade-off.
+ *
+ * Complexity: O(sampleSize) - constant time regardless of graph size.
+ */
+function estimateCrossingRatio(
+    positions: Record<string, Position>,
+    edges: EdgeForCrossing[],
+    sampleSize: number
+): number {
+    let crossings = 0;
+    let validSamples = 0;
+    const maxSamples = Math.min(sampleSize, edges.length * (edges.length - 1) / 2);
+
+    for (let s = 0; s < maxSamples; s++) {
+        // Pick two random distinct edges
+        const i = Math.floor(Math.random() * edges.length);
+        let j = Math.floor(Math.random() * (edges.length - 1));
+        if (j >= i) j++; // Ensure j ≠ i
+
+        const e1 = edges[i];
+        const e2 = edges[j];
+
+        // Same logic as exact method
+        if (edgesShareNode(e1, e2)) continue;
+
+        const p1 = positions[e1.fromId];
+        const p2 = positions[e1.toId];
+        const p3 = positions[e2.fromId];
+        const p4 = positions[e2.toId];
+        if (!p1 || !p2 || !p3 || !p4) continue;
+
+        validSamples++;
+
+        if (!boundingBoxesOverlap(p1, p2, p3, p4)) continue;
+
+        if (segmentsIntersect(p1, p2, p3, p4)) {
+            crossings++;
+        }
+    }
+
+    return validSamples > 0 ? crossings / validSamples : 0;
+}
+
+// ═══════════════════════════════════════════════════════════════════════════
+// GEOMETRIC UTILITIES
+// ═══════════════════════════════════════════════════════════════════════════
+
+/**
+ * Check if two edges share a common node (endpoint).
+ */
+function edgesShareNode(e1: EdgeForCrossing, e2: EdgeForCrossing): boolean {
+    return (
+        e1.fromId === e2.fromId ||
+        e1.fromId === e2.toId ||
+        e1.toId === e2.fromId ||
+        e1.toId === e2.toId
+    );
+}
+
+/**
+ * Fast rejection: Check if bounding boxes of two line segments overlap.
+ * Eliminates ~90% of pairs without expensive intersection test.
+ */
+function boundingBoxesOverlap(
+    p1: Position,
+    p2: Position,
+    p3: Position,
+    p4: Position
+): boolean {
+    const minX1 = Math.min(p1.x, p2.x);
+    const maxX1 = Math.max(p1.x, p2.x);
+    const minY1 = Math.min(p1.y, p2.y);
+    const maxY1 = Math.max(p1.y, p2.y);
+
+    const minX2 = Math.min(p3.x, p4.x);
+    const maxX2 = Math.max(p3.x, p4.x);
+    const minY2 = Math.min(p3.y, p4.y);
+    const maxY2 = Math.max(p3.y, p4.y);
+
+    // Boxes overlap if they're NOT separated in either axis
+    return !(maxX1 < minX2 || maxX2 < minX1 || maxY1 < minY2 || maxY2 < minY1);
+}
+
+/**
+ * Line segment intersection test using cross products.
+ * Returns true if segments (p1,p2) and (p3,p4) intersect in their interior.
+ *
+ * Algorithm: Parametric line equations + cross products
+ * - Line 1: p1 + t1 * (p2 - p1), where t1 ∈ [0, 1]
+ * - Line 2: p3 + t2 * (p4 - p3), where t2 ∈ [0, 1]
+ * - Segments intersect if both t1 and t2 are in [0, 1]
+ */
+function segmentsIntersect(
+    p1: Position,
+    p2: Position,
+    p3: Position,
+    p4: Position
+): boolean {
+    // Direction vectors
+    const d1x = p2.x - p1.x;
+    const d1y = p2.y - p1.y;
+    const d2x = p4.x - p3.x;
+    const d2y = p4.y - p3.y;
+
+    // Vector from p1 to p3
+    const d3x = p3.x - p1.x;
+    const d3y = p3.y - p1.y;
+
+    // Cross product of d1 and d2 (determinant)
+    const cross = d1x * d2y - d1y * d2x;
+
+    // Parallel or collinear - no intersection (or infinite intersections)
+    if (Math.abs(cross) < 1e-10) return false;
+
+    // Solve for parametric t values
+    const t1 = (d3x * d2y - d3y * d2x) / cross;
+    const t2 = (d3x * d1y - d3y * d1x) / cross;
+
+    // Intersection exists if both parameters are in [0, 1]
+    return t1 >= 0 && t1 <= 1 && t2 >= 0 && t2 <= 1;
+}
diff --git a/src/graph/simulation/engines/webColaEngine.ts b/src/graph/simulation/engines/webColaEngine.ts
index 531c1ee..8c08434 100644
--- a/src/graph/simulation/engines/webColaEngine.ts
+++ b/src/graph/simulation/engines/webColaEngine.ts
@@ -18,6 +18,8 @@ import {
     PinStatus,
 } from "../types";
 import { NestedGraphData } from "../../preprocess/nestGraphData";
+// MODULAR: Edge crossing detector (delete this line + 1 function call to remove)
+import { hasGoodLayout } from "../edgeCrossingDetector";
 
 // ═══════════════════════════════════════════════════════════════════════════
 // CUSTOM LAYOUT WITH EXPOSED TICK
@@ -286,10 +288,27 @@ export class WebColaEngine implements SimulationEngine {
             this.initialized = true;
 
             if (isFirstInit) {
-                // First initialization: start without constraints, apply after delay
-                this.lastMutationTime = performance.now();
-                this.constraintsApplied = false;
-                this.rebuildLayout(false);
+                // MODULAR: Check if saved positions are high quality (few edge crossings)
+                // DELETE these 5 lines to always use two-phase init:
+                const edges = Object.values(graph.dependencies).map(dep => ({
+                    fromId: dep.data.fromId,
+                    toId: dep.data.toId
+                }));
+                const hasGoodSavedLayout = hasGoodLayout(prevState.positions, edges);
+
+                if (hasGoodSavedLayout) {
+                    // Saved positions are good quality - skip unconstrained phase
+                    console.log("[WebCola] Preserved saved positions (good layout detected)");
+                    this.constraintsApplied = true;
+                    this.lastMutationTime = null;
+                    this.rebuildLayout(true);
+                } else {
+                    // Saved positions are poor quality or missing - do two-phase init
+                    console.log("[WebCola] Starting two-phase init (edge crossings detected or no saved positions)");
+                    this.lastMutationTime = performance.now();
+                    this.constraintsApplied = false;
+                    this.rebuildLayout(false);
+                }
             } else {
                 // Subsequent changes: go straight to constrained layout
                 this.constraintsApplied = true;
diff --git a/src/graph/simulation/index.ts b/src/graph/simulation/index.ts
index 2d3f2f9..ca6d232 100644
--- a/src/graph/simulation/index.ts
+++ b/src/graph/simulation/index.ts
@@ -7,3 +7,5 @@
 export * from "./types";
 export * from "./utils";
 export * from "./engines";
+// TEMPORARY: Position persistence (remove when backend storage exists)
+export * from "./PositionPersistenceManager";
diff --git a/src/stores/todoStore.ts b/src/stores/todoStore.ts
index a495d53..2442889 100644
--- a/src/stores/todoStore.ts
+++ b/src/stores/todoStore.ts
@@ -1,6 +1,6 @@
 import { create } from 'zustand';
 import {
-    type TaskListOut,
+    type NodeListOut,
     DefaultApi,
     Configuration,
     subscribeToTasks,
@@ -17,7 +17,7 @@ export type ConnectionStatus = 'disconnected' | 'connecting' | 'connected' | 'er
 
 interface TodoStore {
     // State
-    graphData: TaskListOut | null;
+    graphData: NodeListOut | null;
     cursor: string | null;
     navInfoText: string | null;
     navigationMode: NavigationMode;
@@ -91,12 +91,14 @@ export const useTodoStore = create<TodoStore>((set, get) => ({
         const api = new DefaultApi(new Configuration({ basePath: baseUrl }));
 
         const unsubscribe = subscribeToTasks(
-            (data) => set({
-                graphData: data,
-                connectionStatus: 'connected',
-                lastDataReceived: Date.now(),
-                lastError: null,
-            }),
+            (data) => {
+                set({
+                    graphData: data,
+                    connectionStatus: 'connected',
+                    lastDataReceived: Date.now(),
+                    lastError: null,
+                });
+            },
             {
                 baseUrl,
                 onError: (err) => {

