# Neo4j Kubernetes Backup Notes

Date: 2026-02-22
Cluster context: `k3s-ldn`

## What was discovered
- GitOps repo path used: `/mnt/workspace/repos/k3s-ldn-gitops`
- ArgoCD app manifest: `infra/apps/todo.yaml`
- Neo4j workload manifest: `apps/todo/deployment.yaml`
- Neo4j namespace: `todo`
- Neo4j pod label: `app=neo4j`
- Neo4j PVC: `neo4j-data`
- Neo4j data mount path in container: `/data`

## PVC/PV verification
```bash
kubectl -n todo get pvc neo4j-data -o wide
```
Result (key fields):
- STATUS: `Bound`
- STORAGECLASS: `longhorn`
- VOLUME: `pvc-1244edea-abdd-41ff-9417-8d853f6d0c36`

```bash
PV=$(kubectl -n todo get pvc neo4j-data -o jsonpath='{.spec.volumeName}')
kubectl get pv "$PV" -o wide
```
Result (key fields):
- PV: `pvc-1244edea-abdd-41ff-9417-8d853f6d0c36`
- CLAIM: `todo/neo4j-data`
- RECLAIM POLICY: `Delete`
- VOLUMEMODE: `Filesystem`

## Backup performed
A tar.gz archive of Neo4j `/data` was created inside the running pod, copied locally, then removed from pod tmp storage.

```bash
set -euo pipefail
TS=$(date +%Y%m%d-%H%M%S)
NS=todo
POD=$(kubectl -n "$NS" get pod -l app=neo4j -o jsonpath='{.items[0].metadata.name}')
OUTDIR=/mnt/workspace/repos/libopenscale/backups/neo4j
ARCHIVE=neo4j-data-${TS}.tar.gz
mkdir -p "$OUTDIR"
kubectl -n "$NS" exec "$POD" -- sh -lc "tar -czf /tmp/${ARCHIVE} -C / data"
kubectl -n "$NS" cp "$POD:/tmp/${ARCHIVE}" "$OUTDIR/${ARCHIVE}"
kubectl -n "$NS" exec "$POD" -- rm -f "/tmp/${ARCHIVE}"
sha256sum "$OUTDIR/${ARCHIVE}"
ls -lh "$OUTDIR/${ARCHIVE}"
```

## Actual backup artifact created
- Pod used: `neo4j-547f554585-628rd`
- File: `/mnt/workspace/repos/libopenscale/backups/neo4j/neo4j-data-20260222-011015.tar.gz`
- SHA256: `de784f287c390743834195555e0190d0959d56cb74846780916fbb4707aaa1ef`
- Size: `660K`

## Archive sanity check
```bash
tar -tzf /mnt/workspace/repos/libopenscale/backups/neo4j/neo4j-data-20260222-011015.tar.gz | head -n 25
```
The archive contains expected Neo4j files under:
- `data/databases/neo4j/...`
- `data/transactions/neo4j/...`
- `data/transactions/system/...`

## Snapshot capability check
Checked for Kubernetes CSI VolumeSnapshot APIs/CRDs and found none installed in this cluster at the time of backup.
