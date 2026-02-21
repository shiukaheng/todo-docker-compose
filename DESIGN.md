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

- plan (claude please fill in how we have this right now, what data do we have on it? the main point is that a plan is essentially a list of nodes. thats all! its meant to denote a sequence of nodes we intend to fulfill. the key is it documents INTENT! the plan does not have to be valid. for now, these plans are created manually, but later on they may be created automatically.)

these nodes can then have a directional edge to another node, denoting a dependency, i.e., A -(depends on)-> B

in order to make this graph valid for subsequent calculations, a graph is ONLY valid if it is a directed acyclic graph (DAG).

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

after these operations, each node will have an extra:
    - calculated_completed: int (TODO: we need to think of a way to propagate the time completed though)
    - calculated_due: int

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
subscribe -> subscribes to any graph changes. essentially: core + inferred + metadata
subscribe_display -> subscribes to any changes in display layer (views for now essentially)

read (request) operations:
(fill this in claude!)

write operations:
mutate -> ... (claude please fill in!)
mutate_display -> ... (fill in)

(im keeping the core / display data seperate as they may have very different access patterns / could be potentially stored on different DBs in the future)

# qol

optimistic updates: our client should be able to predict client side modifications of all mutate operations easily (they are fairly simple..); IMPLEMENTATIONAL DETAIL: but i dont want to pollute our autogenerated client. thats nice. instead, we will probably create a wrapper on the existing client so that we can inject optimistic update logic on top of the existing client.

# extensions

## multiplayer

easiest extension: people are still working in a single, big graph. 

now though, nodes are simply attached with new information regarding who can read them, and who can write them. edges are derivative information of nodes, thus a user will have the minimum of the two permission sets of the nodes as the permissions to access the edge.

lets think of this more later on.