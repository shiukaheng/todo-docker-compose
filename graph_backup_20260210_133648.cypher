// Neo4j Graph Backup - Cypher Format
// Created: Tue Feb 10 01:36:48 PM GMT 2026
// Nodes: 19, Relationships: 17

// Node: (:Task {inferred: FALSE, created_at: 1770717897, id: "internship-decision", completed: FALSE, updated_at: 1770717897})
// Node: (:Task {inferred: FALSE, created_at: 1770717882, id: "mxr-e", completed: FALSE, updated_at: 1770717882})
// Node: (:Task {inferred: FALSE, created_at: 1770714544, completed: FALSE, id: "sample-train", updated_at: 1770714544})
// Node: (:Task {inferred: FALSE, created_at: 1770714531, completed: FALSE, id: "mxr-feb-10", updated_at: 1770714531})
// Node: (:Task {inferred: FALSE, created_at: 1770717784, completed: FALSE, id: "rebook-dentist", updated_at: 1770717784})
// Node: (:Task {inferred: FALSE, created_at: 1770717816, id: "make-sure-6-working-scans", completed: FALSE, updated_at: 1770717816})
// Node: (:Task {inferred: TRUE, created_at: 1770717824, completed: FALSE, id: "all-mask-ok", updated_at: 1770719132})
// Node: (:Task {inferred: TRUE, created_at: 1770717838, completed: FALSE, text: "Depth reinitialization works as expected", id: "depth-reinit-fix", updated_at: 1770719118})
// Node: (:Task {inferred: FALSE, created_at: 1770717926, completed: FALSE, id: "consult-jasper", updated_at: 1770717926})
// Node: (:Task {inferred: FALSE, created_at: 1770717945, completed: FALSE, id: "consult-mo", updated_at: 1770717945})
// Node: (:Task {inferred: FALSE, created_at: 1770717962, completed: FALSE, id: "consult-elliott", updated_at: 1770717962})
// Node: (:Task {updated_at: 1770723004, due: 1770723374, inferred: FALSE, created_at: 1770718858, id: "disable-depth-trunc", text: "Don't use an arbitrary threshold to cap reinitialized points", completed: TRUE})
// Node: (:Task {updated_at: 1770723007, due: 1770730588, inferred: FALSE, created_at: 1770718974, id: "multi-mask-propagate", text: "Improve masking algorithm: Use multiple prompt masks, union the masks to reduce artifacting", completed: FALSE})
// Node: (:Task {inferred: FALSE, created_at: 1770720368, completed: FALSE, id: "pbrgs-vis", updated_at: 1770720368})
// Node: (:Task {inferred: FALSE, created_at: 1770727591, completed: FALSE, id: "trip-planning", updated_at: 1770727591})
// Node: (:Task {inferred: FALSE, created_at: 1770727605, id: "crete", completed: FALSE, updated_at: 1770727605})
// Node: (:Task {inferred: FALSE, created_at: 1770727613, completed: FALSE, id: "morocco", updated_at: 1770727613})
// Node: (:Task {inferred: FALSE, created_at: 1770727623, id: "spain", completed: FALSE, updated_at: 1770727623})
// Node: (:Task {inferred: FALSE, created_at: 1770727627, completed: FALSE, id: "portugal", updated_at: 1770727627})
statement
"CREATE (n0:Task {id: \"internship-decision\", completed: false, inferred: false, created_at: 1770717897, updated_at: 1770717897});"
"CREATE (n1:Task {id: \"mxr-e\", completed: false, inferred: false, created_at: 1770717882, updated_at: 1770717882});"
"CREATE (n2:Task {id: \"sample-train\", completed: false, inferred: false, created_at: 1770714544, updated_at: 1770714544});"
"CREATE (n3:Task {id: \"mxr-feb-10\", completed: false, inferred: false, created_at: 1770714531, updated_at: 1770714531});"
"CREATE (n4:Task {id: \"rebook-dentist\", completed: false, inferred: false, created_at: 1770717784, updated_at: 1770717784});"
"CREATE (n5:Task {id: \"make-sure-6-working-scans\", completed: false, inferred: false, created_at: 1770717816, updated_at: 1770717816});"
"CREATE (n6:Task {id: \"all-mask-ok\", completed: false, inferred: true, created_at: 1770717824, updated_at: 1770719132});"
"CREATE (n7:Task {id: \"depth-reinit-fix\", text: \"Depth reinitialization works as expected\", completed: false, inferred: true, created_at: 1770717838, updated_at: 1770719118});"
"CREATE (n8:Task {id: \"consult-jasper\", completed: false, inferred: false, created_at: 1770717926, updated_at: 1770717926});"
"CREATE (n9:Task {id: \"consult-mo\", completed: false, inferred: false, created_at: 1770717945, updated_at: 1770717945});"
"CREATE (n10:Task {id: \"consult-elliott\", completed: false, inferred: false, created_at: 1770717962, updated_at: 1770717962});"
"CREATE (n11:Task {id: \"disable-depth-trunc\", text: \"Don't use an arbitrary threshold to cap reinitialized points\", completed: true, inferred: false, due: 1770723374, created_at: 1770718858, updated_at: 1770723004});"
"CREATE (n12:Task {id: \"multi-mask-propagate\", text: \"Improve masking algorithm: Use multiple prompt masks, union the masks to reduce artifacting\", completed: false, inferred: false, due: 1770730588, created_at: 1770718974, updated_at: 1770723007});"
"CREATE (n13:Task {id: \"pbrgs-vis\", completed: false, inferred: false, created_at: 1770720368, updated_at: 1770720368});"
"CREATE (n14:Task {id: \"trip-planning\", completed: false, inferred: false, created_at: 1770727591, updated_at: 1770727591});"
"CREATE (n15:Task {id: \"crete\", completed: false, inferred: false, created_at: 1770727605, updated_at: 1770727605});"
"CREATE (n16:Task {id: \"morocco\", completed: false, inferred: false, created_at: 1770727613, updated_at: 1770727613});"
"CREATE (n17:Task {id: \"spain\", completed: false, inferred: false, created_at: 1770727623, updated_at: 1770727623});"
"CREATE (n18:Task {id: \"portugal\", completed: false, inferred: false, created_at: 1770727627, updated_at: 1770727627});"

statement
"MATCH (a:Task {id: \"mxr-e\"}), (b:Task {id: \"internship-decision\"}) CREATE (a)-[:DEPENDS_ON {id: \"722fe5c9-926d-4826-a5a7-0fdfa79afcb3\"}]->(b);"
"MATCH (a:Task {id: \"mxr-feb-10\"}), (b:Task {id: \"sample-train\"}) CREATE (a)-[:DEPENDS_ON {id: \"e5b45b84-73df-4322-91c4-c7f10cdd110c\"}]->(b);"
"MATCH (a:Task {id: \"mxr-e\"}), (b:Task {id: \"mxr-feb-10\"}) CREATE (a)-[:DEPENDS_ON {id: \"ee742acc-f964-44bd-962f-2630c28f398b\"}]->(b);"
"MATCH (a:Task {id: \"mxr-feb-10\"}), (b:Task {id: \"rebook-dentist\"}) CREATE (a)-[:DEPENDS_ON {id: \"059f8f0f-f40a-4e95-9e06-7fb14b0088de\"}]->(b);"
"MATCH (a:Task {id: \"sample-train\"}), (b:Task {id: \"make-sure-6-working-scans\"}) CREATE (a)-[:DEPENDS_ON {id: \"9ba5db3f-0979-42d0-bc74-6ea0f5953a98\"}]->(b);"
"MATCH (a:Task {id: \"make-sure-6-working-scans\"}), (b:Task {id: \"all-mask-ok\"}) CREATE (a)-[:DEPENDS_ON {id: \"20d893a8-e569-4d10-944c-548a61b6be26\"}]->(b);"
"MATCH (a:Task {id: \"make-sure-6-working-scans\"}), (b:Task {id: \"depth-reinit-fix\"}) CREATE (a)-[:DEPENDS_ON {id: \"6841f9d9-e939-4bdb-8ebc-fede72a68ba6\"}]->(b);"
"MATCH (a:Task {id: \"consult-mo\"}), (b:Task {id: \"consult-jasper\"}) CREATE (a)-[:DEPENDS_ON {id: \"79f5c3eb-1068-487e-a970-61974f8ed572\"}]->(b);"
"MATCH (a:Task {id: \"consult-elliott\"}), (b:Task {id: \"consult-mo\"}) CREATE (a)-[:DEPENDS_ON {id: \"7aeeb565-ee40-43bf-9244-ed3c07b7a6d3\"}]->(b);"
"MATCH (a:Task {id: \"internship-decision\"}), (b:Task {id: \"consult-elliott\"}) CREATE (a)-[:DEPENDS_ON {id: \"05530ec8-3a3d-4718-b5e3-fa7ccea75e18\"}]->(b);"
"MATCH (a:Task {id: \"depth-reinit-fix\"}), (b:Task {id: \"disable-depth-trunc\"}) CREATE (a)-[:DEPENDS_ON {id: \"9349145a-2f26-40d0-bc69-f1f4982a6245\"}]->(b);"
"MATCH (a:Task {id: \"all-mask-ok\"}), (b:Task {id: \"multi-mask-propagate\"}) CREATE (a)-[:DEPENDS_ON {id: \"b8160503-72cd-435f-baa6-e450f2e46ab1\"}]->(b);"
"MATCH (a:Task {id: \"mxr-e\"}), (b:Task {id: \"pbrgs-vis\"}) CREATE (a)-[:DEPENDS_ON {id: \"6b0b77e7-3759-449a-841a-a07330b7da72\"}]->(b);"
"MATCH (a:Task {id: \"trip-planning\"}), (b:Task {id: \"crete\"}) CREATE (a)-[:DEPENDS_ON {id: \"e8a1f7d5-5130-451f-96ac-c502617fb858\"}]->(b);"
"MATCH (a:Task {id: \"trip-planning\"}), (b:Task {id: \"morocco\"}) CREATE (a)-[:DEPENDS_ON {id: \"38a612b5-1589-4aa5-9e43-6b3c6f85f66f\"}]->(b);"
"MATCH (a:Task {id: \"trip-planning\"}), (b:Task {id: \"spain\"}) CREATE (a)-[:DEPENDS_ON {id: \"61804e29-770c-49b4-bf77-3ccfbfc6071a\"}]->(b);"
"MATCH (a:Task {id: \"trip-planning\"}), (b:Task {id: \"portugal\"}) CREATE (a)-[:DEPENDS_ON {id: \"a59dcda0-c410-412b-af62-399a6d8f18e2\"}]->(b);"
