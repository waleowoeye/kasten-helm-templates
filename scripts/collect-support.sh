#!/usr/bin/env bash
set -euo pipefail

NS="${1:-kasten-io}"
OUTDIR="${2:-./artifacts}"
TS="${3:-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$OUTDIR"
BUNDLE_DIR="$OUTDIR/support-${TS}"
mkdir -p "$BUNDLE_DIR"

echo "[INFO] Collecting Kasten + cluster debug artifacts into $BUNDLE_DIR"

# 1) Kasten official support bundle
DEBUG_URL="https://docs.kasten.io/downloads/8.5.9/tools/k10_debug.sh"
(curl -s "$DEBUG_URL" | bash -s -- -n "$NS" -o "$BUNDLE_DIR/k10_debug_logs.tar.gz") || true

# 2) Cluster state (safe, read-only)
(
  echo "# nodes"; kubectl get nodes -o wide
  echo; echo "# sc"; kubectl get sc -o yaml
  echo; echo "# csidriver"; kubectl get csidriver -o yaml || true
  echo; echo "# volumesnapshotclass"; kubectl get volumesnapshotclass -o yaml || true
  echo; echo "# events (namespace)"; kubectl get events -n "$NS" --sort-by=.metadata.creationTimestamp || true
  echo; echo "# pods"; kubectl get pods -n "$NS" -o wide || true
  echo; echo "# services"; kubectl get svc -n "$NS" -o yaml || true
  echo; echo "# ingress/routes"; kubectl get ingress -A -o yaml || true
  echo; echo "# routes (openshift)"; kubectl get route -A -o yaml || true
) > "$BUNDLE_DIR/cluster-snapshot.txt" 2>&1 || true

# 3) Helm state (best-effort)
helm -n "$NS" status k10 > "$BUNDLE_DIR/helm-status.txt" 2>&1 || true
helm -n "$NS" get values k10 --all > "$BUNDLE_DIR/helm-values-all.yaml" 2>&1 || true

# 4) Package for upload
(cd "$OUTDIR" && tar -czf "support-${TS}.tar.gz" "support-${TS}")

echo "[INFO] Created: $OUTDIR/support-${TS}.tar.gz"
