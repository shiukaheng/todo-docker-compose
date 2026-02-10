#!/bin/bash
# Backup Neo4j graph data before schema migration

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="graph_backup_${TIMESTAMP}.json"

echo "Backing up Neo4j graph data to ${BACKUP_FILE}..."

# Export all nodes and relationships as JSON
docker exec todo-docker-compose-neo4j-1 cypher-shell \
  -u neo4j \
  -p password \
  "MATCH (n)
   OPTIONAL MATCH (n)-[r]->(m)
   WITH collect(DISTINCT n) as nodes, collect(DISTINCT r) as rels
   RETURN {
     nodes: [node IN nodes | {
       id: id(node),
       labels: labels(node),
       properties: properties(node)
     }],
     relationships: [rel IN rels WHERE rel IS NOT NULL | {
       id: id(rel),
       type: type(rel),
       startNode: id(startNode(rel)),
       endNode: id(endNode(rel)),
       properties: properties(rel)
     }]
   } as graph" > "${BACKUP_FILE}"

echo "Backup complete: ${BACKUP_FILE}"
echo ""
echo "To restore this backup later, you can use the restore script."
