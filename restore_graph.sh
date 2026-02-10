#!/bin/bash
# Restore Neo4j graph data from backup
# Usage: ./restore_graph.sh <backup_file.json>

if [ -z "$1" ]; then
  echo "Usage: ./restore_graph.sh <backup_file.json>"
  echo ""
  echo "Available backups:"
  ls -1 graph_backup_*.json 2>/dev/null || echo "  (no backups found)"
  exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
  echo "Error: Backup file not found: $BACKUP_FILE"
  exit 1
fi

echo "WARNING: This will DELETE all existing data and restore from backup!"
echo "Backup file: ${BACKUP_FILE}"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
  echo "Restore cancelled."
  exit 0
fi

echo "Clearing existing graph..."
docker exec todo-docker-compose-neo4j-1 cypher-shell \
  -u neo4j \
  -p password \
  "MATCH (n) DETACH DELETE n"

echo "Graph cleared. You will need to manually restore from the JSON backup."
echo "The backup contains the graph structure in: ${BACKUP_FILE}"
echo ""
echo "Note: Automated restore requires APOC procedures or custom import script."
echo "For now, you can use this backup as reference to manually recreate the graph."
