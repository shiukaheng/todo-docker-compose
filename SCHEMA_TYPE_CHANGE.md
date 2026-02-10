# Changing Node Types

## Type is Stored in Labels

Node type is determined by its label: `:Task`, `:And`, `:Or`, `:Not`, `:ExactlyOne`

All nodes also have `:Node` label for unified queries.

## Changing Type

### Task → And
```cypher
MATCH (n:Task {id: $id})
REMOVE n:Task
SET n:And
REMOVE n.completed  // Gates don't have completed property
SET n.updated_at = timestamp()
```

### Task → Or
```cypher
MATCH (n:Task {id: $id})
REMOVE n:Task
SET n:Or
REMOVE n.completed
SET n.updated_at = timestamp()
```

### Task → Not
```cypher
MATCH (n:Task {id: $id})
REMOVE n:Task
SET n:Not
REMOVE n.completed
SET n.updated_at = timestamp()
```

### Task → ExactlyOne
```cypher
MATCH (n:Task {id: $id})
REMOVE n:Task
SET n:ExactlyOne
REMOVE n.completed
SET n.updated_at = timestamp()
```

### And → Task (or any Gate → Task)
```cypher
MATCH (n:And {id: $id})
REMOVE n:And
SET n:Task, n.completed = false  // Add completed property
SET n.updated_at = timestamp()
```

### Gate → Gate (e.g., And → Or)
```cypher
MATCH (n:And {id: $id})
REMOVE n:And
SET n:Or
SET n.updated_at = timestamp()
```

## General Pattern

```cypher
MATCH (n:OldType {id: $id})
REMOVE n:OldType
SET n:NewType
// If converting TO Task: SET n.completed = false
// If converting FROM Task: REMOVE n.completed
SET n.updated_at = timestamp()
```

## Reading Node Type in Backend

```python
# Get labels from query
result = tx.run("MATCH (n:Node {id: $id}) RETURN n, labels(n) as labels", id=id)
record = result.single()

labels = record["labels"]
# labels = ["Node", "Task"] or ["Node", "And"], etc.

# Extract type (the non-Node label)
node_type = next((l for l in labels if l != "Node"), None)
# node_type = "Task" or "And" or "Or" or "Not" or "ExactlyOne"
```

## Creating Nodes

```cypher
// Create Task
CREATE (n:Node:Task {
  id: $id,
  text: $text,
  completed: false,
  created_at: timestamp(),
  updated_at: timestamp()
})

// Create And gate
CREATE (n:Node:And {
  id: $id,
  text: $text,
  created_at: timestamp(),
  updated_at: timestamp()
})
```

## Querying by Type

```cypher
// All tasks
MATCH (t:Task) RETURN t

// All And gates
MATCH (g:And) RETURN g

// All gates (any type)
MATCH (n:Node) WHERE NOT n:Task RETURN n

// All nodes of multiple types
MATCH (n) WHERE n:And OR n:Or RETURN n
```
