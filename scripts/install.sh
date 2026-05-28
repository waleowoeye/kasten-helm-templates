#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/install.sh <overlay-yaml> [storageClass] [k10-namespace]
# Examples:
#   ./scripts/install.sh values-multicluster.yaml
#   ./scripts/install.sh values-multicluster.yaml gp3
#   ./scripts/install.sh values-multicluster.yaml ocs-storagecluster-ceph-rbd kasten-io

ENV_OVERLAY=${1:-values-multicluster.yaml}
STORAGE_CLASS=${2:-""}
NS=${3:-kasten-io}

OUTDIR=${OUTDIR:-./artifacts}
TS="$(date +%Y%m%d-%H%M%S)"
LOGDIR="${OUTDIR}/install-${TS}"
mkdir -p "${LOGDIR}"

PRE_LOG="${LOGDIR}/preflight.log"
PRE_RC_FILE="${LOGDIR}/preflight.rc"
EVENTS_FAILED="${LOGDIR}/events_failed.txt"
BASIC_SNAPSHOT="${LOGDIR}/cluster_snapshot.txt"
K10_DEBUG_TGZ="${LOGDIR}/k10_debug_logs.tar.gz"

# Prefer oc if present, else kubectl
K=kubectl
if command -v oc >/dev/null 2>&1; then
  K=oc
fi

info(){ echo "[INFO] $*"; }
warn(){ echo "[WARN] $*"; }
err(){ echo "[ERROR] $*"; }

collect_troubleshooting() {
  warn "Collecting troubleshooting artifacts into ${LOGDIR}"

  # 1) Your requested data: failed events in kasten namespace
  # Note: this is explicitly referenced in your internal bookmarks for troubleshooting.
  ${K} get events -n "${NS}" --sort-by='.metadata.creationTimestamp' 2>&1 \
    | grep -i failed > "${EVENTS_FAILED}" || true

  # 2) Helpful cluster snapshots (read-only)
  {
    echo "# context"; ${K} config current-context 2>&1 || true; echo
    echo "# nodes"; ${K} get nodes -o wide 2>&1 || true; echo
    echo "# storageclasses"; ${K} get sc 2>&1 || true; echo
    echo "# csidrivers"; ${K} get csidriver 2>&1 || true; echo
    echo "# volumesnapshotclasses"; ${K} get volumesnapshotclass 2>&1 || true; echo
    echo "# pods (namespace)"; ${K} get pods -n "${NS}" -o wide 2>&1 || true; echo
    echo "# svc (namespace)"; ${K} get svc -n "${NS}" 2>&1 || true; echo
  } > "${BASIC_SNAPSHOT}"

  # 3) Official Kasten support bundle (recommended by docs)
  # Produces a tar.gz bundle with service logs; good for SRs.
  curl -s https://docs.kasten.io/downloads/8.5.9/tools/k10_debug.sh \
    | bash -s -- -n "${NS}" -o "${K10_DEBUG_TGZ}" || true
}

run_preflight() {
  info "Running Kasten official preflight (k10_primer.sh) …"
  # Install requirements doc recommends running pre-flight checks with k10_primer.sh.
  # You can pin version or update to match your desired K10 release.
  PRIMER_URL="https://docs.kasten.io/downloads/8.5.9/tools/k10_primer.sh"

  set +e
  if [[ -n "${STORAGE_CLASS}" ]]; then
    # CSI checker mode used in PoC templates: primer + csi -s <storageClass>
    curl -s "${PRIMER_URL}" | bash /dev/stdin csi -s "${STORAGE_CLASS}" 2>&1 | tee "${PRE_LOG}"
    RC=${PIPESTATUS[2]}
  else
    curl -s "${PRIMER_URL}" | bash 2>&1 | tee "${PRE_LOG}"
    RC=${PIPESTATUS[2]}
  fi
  set -e

  echo "${RC}" > "${PRE_RC_FILE}"
  return "${RC}"
}

main() {
  # 0) ensure helm repo is present (idempotent)
  helm repo add kasten https://charts.kasten.io/ 2>/dev/null || true
  helm repo update >/dev/null

  # 1) preflight gate
  if ! run_preflight; then
    err "Preflight FAILED (rc=$(cat "${PRE_RC_FILE}"))."
    collect_troubleshooting
    err "Artifacts collected in: ${LOGDIR}"
    err "Key files:"
    err "  - ${PRE_LOG}"
    err "  - ${EVENTS_FAILED}"
    err "  - ${K10_DEBUG_TGZ} (if generated)"
    exit 1
  fi

  info "Preflight PASSED. Proceeding with install."

  # 2) install (only for first-time; upgrades are handled separately)
  helm install k10 kasten/k10 \
    -f base-values.yaml \
    -f "overlays/${ENV_OVERLAY}" \
    -n "${NS}" \
    --create-namespace

  info "Install complete."
  info "Artifacts (preflight log) saved in: ${LOGDIR}"
}

main "$@"
