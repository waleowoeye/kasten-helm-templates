#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------
# Usage:
#   ./scripts/install.sh [--dry-run] <overlay-yaml> [storageClass] [namespace]
#
# Examples:
#   ./scripts/install.sh values-multicluster.yaml
#   ./scripts/install.sh --dry-run values-multicluster.yaml
#   ./scripts/install.sh values-multicluster.yaml gp3
# ----------------------------------------

# Detect dry-run flag
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  shift
fi

ENV_OVERLAY=${1:-values-multicluster.yaml}
STORAGE_CLASS=${2:-""}
NS=${3:-kasten-io}

OUTDIR=${OUTDIR:-./artifacts}
TS="$(date +%Y%m%d-%H%M%S)"
LOGDIR="${OUTDIR}/install-${TS}"
mkdir -p "${LOGDIR}"

PRE_LOG="${LOGDIR}/primer.log"
NEXT_STEPS="${LOGDIR}/next-steps.txt"
EVENTS_FAILED="${LOGDIR}/events_failed.txt"
SNAPSHOT="${LOGDIR}/cluster_snapshot.txt"

# Prefer oc if present (OpenShift), else kubectl
K=kubectl
command -v oc >/dev/null 2>&1 && K=oc

info(){ echo "[INFO] $*"; }
warn(){ echo "[WARN] $*"; }
err(){  echo "[ERROR] $*"; }

# ----------------------------------------
# Collect cluster baseline
# ----------------------------------------
collect_basics() {
  {
    echo "# context"; ${K} config current-context 2>&1 || true; echo
    echo "# versions"; ${K} version --short 2>&1 || true; helm version 2>&1 || true; echo
    echo "# nodes"; ${K} get nodes -o wide 2>&1 || true; echo
    echo "# storageclasses"; ${K} get sc 2>&1 || true; echo
    echo "# csidrivers"; ${K} get csidriver -o yaml 2>&1 || true; echo
    echo "# volumesnapshotclass"; ${K} get volumesnapshotclass -o yaml 2>&1 || true; echo
    echo "# namespace pods/svc"; ${K} get pods -n "${NS}" -o wide 2>&1 || true; ${K} get svc -n "${NS}" 2>&1 || true; echo
  } > "${SNAPSHOT}" 2>&1 || true
}

# ----------------------------------------
# Collect failed events (your key requirement)
# ----------------------------------------
collect_failed_events() {
  ${K} get events -n "${NS}" \
    --sort-by='.metadata.creationTimestamp' 2>&1 | \
    grep -i failed > "${EVENTS_FAILED}" || true
}

# ----------------------------------------
# Support bundle
# ----------------------------------------
collect_support_bundle() {
  ./scripts/collect-support.sh "${NS}" "${OUTDIR}" "${TS}" >/dev/null 2>&1 || true
}

# ----------------------------------------
# Generate next steps (high signal)
# ----------------------------------------
write_next_steps() {
  : > "${NEXT_STEPS}"

  if grep -qi "Unable to find jq" "${PRE_LOG}"; then
    echo "NEXT: install jq (required by k10_primer.sh)" >> "${NEXT_STEPS}"
  fi

  if grep -qi "Helm repo.*not.*found" "${PRE_LOG}"; then
    echo "NEXT: helm repo add kasten https://charts.kasten.io && helm repo update" >> "${NEXT_STEPS}"
  fi

  if grep -qi "Preflight checks failed" "${PRE_LOG}"; then
    echo "NEXT: review primer.log and collected artifacts for root cause" >> "${NEXT_STEPS}"
  fi

  if grep -qi "Not a supported CSI driver" "${PRE_LOG}"; then
    cat >> "${NEXT_STEPS}" <<EOF
NEXT: CSI issue detected:
  - Verify VolumeSnapshotClass
  - Annotate correct class:
    kubectl annotate volumesnapshotclass <VSC> k10.kasten.io/is-snapshot-class=true
  - Re-run preflight with:
    k10_primer.sh | bash /dev/stdin csi -s <STORAGE_CLASS>
EOF
  fi

  if ${K} get csidriver -o yaml 2>/dev/null | grep -q "fsGroupPolicy: None"; then
    echo "NEXT: fsGroupPolicy=None → expect permission issues; consider fsGroup/runAsUser tuning" >> "${NEXT_STEPS}"
  fi

  if [[ ! -s "${NEXT_STEPS}" ]]; then
    echo "NEXT: no known issue signature. Inspect logs in ${LOGDIR}" >> "${NEXT_STEPS}"
  fi
}

# ----------------------------------------
# Run Kasten preflight
# ----------------------------------------
run_kasten_primer() {
  PRIMER_URL="https://docs.kasten.io/downloads/8.5.9/tools/k10_primer.sh"

  set +e
  if [[ -n "${STORAGE_CLASS}" ]]; then
    curl -s "${PRIMER_URL}" | bash /dev/stdin csi -s "${STORAGE_CLASS}" 2>&1 | tee "${PRE_LOG}"
    RC=${PIPESTATUS[2]}
  else
    curl -s "${PRIMER_URL}" | bash 2>&1 | tee "${PRE_LOG}"
    RC=${PIPESTATUS[2]}
  fi
  set -e

  return ${RC}
}

# ----------------------------------------
# Main
# ----------------------------------------
main() {
  helm repo add kasten https://charts.kasten.io/ 2>/dev/null || true
  helm repo update >/dev/null

  info "Running Kasten preflight"

  if ! run_kasten_primer; then
    err "Preflight FAILED. Collecting troubleshooting data..."

    collect_basics
    collect_failed_events
    collect_support_bundle
    write_next_steps

    echo ""
    echo "========== NEXT STEPS =========="
    cat "${NEXT_STEPS}"
    echo "================================"
    echo ""

    err "Artifacts:"
    err "  - ${PRE_LOG}"
    err "  - ${SNAPSHOT}"
    err "  - ${EVENTS_FAILED}"
    err "  - ${NEXT_STEPS}"
    err "  - ${OUTDIR}/support-${TS}.tar.gz (if created)"

    exit 2
  fi

  info "Preflight PASSED"

  if [[ "${DRY_RUN}" == "true" ]]; then
    info "Dry-run mode enabled → skipping install"
    exit 0
  fi

  info "Installing Kasten"

  helm install k10 kasten/k10 \
    -f base-values.yaml \
    -f "overlays/${ENV_OVERLAY}" \
    -n "${NS}" \
    --create-namespace

  info "Install complete"
}

main "$@"
