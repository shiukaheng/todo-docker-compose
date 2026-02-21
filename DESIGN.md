# overview

this project is a graph based todo / task management system.

the philosophy of this project is simple - the act of working through complex tasks is actually derived from some very simple rules, and we can do effective, complex visualizations on top of that, that gives us a good top down view on tasks, which would be immensely important when you want to be able to make globally informed, coherent decisions, and minimize the stress of context switching when your life has multiple facets.

the ONLY goal is to create a system that allows you to dump tasks with minimal effort, while easily revealing the high level structure of what you are doing. whatever technical decisions are made as a result of this only goal.

the audience of this app is for people who are more technically minded and can work with slightly formalizing their tasks into a machine friendly representation - but i think the key thing that i am abusing here is that humans are already mostly doing planning in the sense of atomic tasks that can depend on other tasks. the learning curve of this system should not be steep - but by re-using familiar and effective interface patterns, we can make this todo system much more frictionless to interface with - with things like clis, tab completion, keyboard shortcuts; things that are quick ways of making a system effortless to work with with a bit of onboarding.

# core data layer

lets start by defining the core data that our system stores. this "core data" layer stores facts that are purely relevant to making decisions - nothing more, nothing less. this is the formal foundation of our todo system, whatever on top of it is for cosmetic / ux reasons.

- node -> an object that defines a concept that can be evaluated to a boolean status (done? not done?).. for which can come in a few flavors:
    - <base>
        - id: str -> unique string to identify this task
        - text: str -> extended, optional text to describe this task
        - due: integer | null -> due date / time in unix time, or null if no due date defined
    - task (an object)
        - completed: integer | null -> completion time in unix time, or null if not completed
    - logic gates: and | or | not | xor

- plan -> an ordered list of nodes, documenting INTENT (a sequence of nodes we intend to fulfill). the plan does not have to be valid — it is purely organizational and does not participate in boolean logic. for now, plans are created manually, but later on they may be created automatically.
    - id: str -> unique string to identify the plan
    - text: str | null -> optional description (e.g., "Q1 Release Plan")
    - steps: an ordered list of references to nodes
        - each step has a float order (allows insertion between steps, e.g., 2.5 between 2.0 and 3.0)
        - steps can reference any node type (task, gate, etc.)
        - no duplicate nodes within a single plan

these nodes can then have a directional edge to another node, denoting a dependency, i.e., A -(depends on)-> B. each edge has its own unique id.

## graph constraints

- the graph MUST be a directed acyclic graph (DAG). cycles are rejected on edge creation.
- node ids are globally unique (across all node types)
- plan ids are globally unique (separate namespace from nodes)
- edge ids are globally unique
- no self-loops (a node cannot depend on itself)
- no duplicate edges (at most one DEPENDS_ON between any two nodes)
- **transitive reduction**: when a new edge is added, any direct edges that are implied by longer paths are automatically removed. e.g., if A→B→C exists and you add A→C, the direct A→C is redundant and gets pruned (or vice versa). this keeps the graph minimal without losing reachability.

and that is it! this is our minimal representation of a task graph.

# inferred data layer

given the above representation of tasks, there is some simple logic rules that we can apply.

- every node, regardless of type, can infer a "calculated_completed" property
    - a task is only calculated_completed, if its own completed property is completed AND for all its depencies, all of them are calculated_completed
    - and: all dependencies are completed
    - or: some dependencies are completed
    - not: really a nor gate
    - xor: only one input is true

- every node, regardless of type, can infer a "calculated_due" property
    - a node's due date can ONLY be earlier than your parents (because causality); in other words, a node's "calculated_due" is the minimum of its own due, and the minimum of all its parents due

additionally, for task nodes specifically:
- deps_clear: bool -> whether this node's dependencies are satisfied according to its gate logic (i.e., can you start working on it?)
- is_actionable: bool -> deps_clear AND NOT completed (a task that is ready to be worked on right now)
    - always false for gate nodes (they are computed automatically)

after these operations, each node will have an extra:
    - calculated_completed: int (TODO: we need to think of a way to propagate the time completed though)
    - calculated_due: int
    - deps_clear: bool
    - is_actionable: bool (tasks only)

## write-side propagation

- **uncompletion propagation**: when a task is marked incomplete, all ancestor tasks (things that depend on it, transitively) that were marked complete get recursively uncompleted. this maintains consistency — a parent task cannot claim to be done if one of its dependencies is no longer done.

# metadata layer

- adding to nodes and edges...
    - created: int
    - modified: int

# display layer

- view (object)
    - positons (dict / map):
        - [node id]: (x, y)
    - node_whitelist: a list of node ids
    - node_blacklist: a list of node ids

how to interpret:

what are views?

everything above so far describes the LOGICAL graph, but it does not care about visualization.

here is how we will do our visualization: when a user views a graph, it will be post-processed with some additional information. this information will then be stored in "view".

first, to plot nodes, nodes need to have a physical position. thus, we use a dict "positions" to store where nodes are. we use a simple dict to associate a node id with its 2d position. in our implementation, there will be no strict checks regarding if there are nodes that are defined here but dont exist; or nodes that arent defined here that do exist. the client will have to correct for this itself.

the way the "positions" dict will be used (just fyi, but it doesnt affect this layer of our system.. it should be agnostic!) is that when a gui client first adopts using a certain "view", it initializes the position to be that described here, removing / adding in whatever is not here / redundant; then the user is free to modify it. the client then regularly updates the position back to the server. while new position updates CAN come from the server (subscription), it no longer updates ui state. it would make sense for a view to be locked to a single client, but its not important for now.

node whitelist / blacklist defines a filter over what nodes we can see in the graph. if both lists are empty, the whole graph is presented to the user. if some node ids are defined in the whitelist, we only show this node, and its recursive children. the blacklist is applied ON TOP OF the whitelisted nodes. if empty, it does nothing. if it has nodes, the node and its recursive children are removed / hidden.

NOTE: this layer is COMPLETELY seperate from the todo system, its effectively a completely separate system JUST for displaying the nodes. only the client cares about this.

# api

read (subscription) operations:
- subscribe -> subscribes to any graph changes via SSE. pushes full state (core + inferred + metadata + plans) on every mutation.
- subscribe_display -> subscribes to any changes in display layer (views for now essentially) [NOT YET IMPLEMENTED]

read (request) operations:
- get state -> returns the full application state (all nodes with computed properties, all dependencies, all plans)
- get node -> returns a single node with computed properties
- list nodes -> returns all nodes with computed properties
- list plans -> returns all plans with steps
- get plan -> returns a single plan with steps

write operations:
- mutate -> a single batch endpoint that accepts an array of typed operations, executed atomically in one transaction. on success, a single SSE broadcast is sent. on failure, the entire transaction rolls back and no broadcast is sent.
    - node operations:
        - create_node(id, text?, completed?, node_type?, due?, depends?, blocks?) -> create a new node. depends/blocks accept lists of node ids to create edges inline.
        - update_node(id, text?, completed?, node_type?, due?) -> update an existing node. only provided fields are changed. setting due to null clears it. changing node_type handles label transitions (e.g., Task→And removes completed property, And→Task adds it).
        - delete_node(id) -> delete a node and all its edges.
        - rename_node(id, new_id) -> change a node's id. fails if new_id already exists.
    - edge operations:
        - link(from_id, to_id) -> create dependency: from_id depends on to_id. validates DAG constraint, runs transitive reduction.
        - unlink(from_id, to_id) -> remove dependency. fails if edge doesn't exist.
    - plan operations:
        - create_plan(id, text?, steps?) -> create a new plan with optional steps.
        - update_plan(id, text?, steps?) -> update a plan. if steps is provided, it replaces all existing steps entirely (not a partial update).
        - delete_plan(id) -> delete a plan and its steps. does NOT delete the referenced nodes.
        - rename_plan(id, new_id) -> change a plan's id. fails if new_id already exists.
- mutate_display -> same atomic batch pattern as mutate, but for display data. [NOT YET IMPLEMENTED]
    - view operations:
        - create_view(id) -> create a new empty view.
        - delete_view(id) -> delete a view.
        - update_positions(view_id, positions) -> merge positions into the view. positions is a partial dict of node_id -> (x, y); existing positions not in the update are left untouched.
        - remove_positions(view_id, node_ids) -> remove specific node positions from the view.
        - set_whitelist(view_id, node_ids) -> replace the entire whitelist.
        - set_blacklist(view_id, node_ids) -> replace the entire blacklist.

(im keeping the core / display data seperate as they may have very different access patterns / could be potentially stored on different DBs in the future)

# qol

optimistic updates: our client should be able to predict client side modifications of all mutate operations easily (they are fairly simple..); IMPLEMENTATIONAL DETAIL: but i dont want to pollute our autogenerated client. thats nice. instead, we will probably create a wrapper on the existing client so that we can inject optimistic update logic on top of the existing client.

# extensions

## multiplayer

easiest extension: people are still working in a single, big graph. 

now though, nodes are simply attached with new information regarding who can read them, and who can write them. edges are derivative information of nodes, thus a user will have the minimum of the two permission sets of the nodes as the permissions to access the edge.

lets think of this more later on.