#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/install.sh <overlay-yaml> [storageClass] [namespace]
# Examples:
#   ./scripts/install.sh values-multicluster.yaml
#   ./scripts/install.sh values-multicluster.yaml gp3

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

collect_basics() {
  {
    echo "# context"; ${K} config current-context 2>&1 || true; echo
    echo "# versions"; ${K} version --short 2>&1 || true; helm version 2>&1 || true; echo
    echo "# nodes"; ${K} get nodes -o wide 2>&1 || true; echo
    echo "# storageclasses"; ${K} get sc 2>&1 || true; echo
    echo "# csidrivers"; ${K} get csidriver -o yaml 2>&1 || true; echo
    echo "# volumesnapshotclass"; ${K} get volumesnapshotclass -o yaml 2>&1 || true; echo
    echo "# namespace pods/svc (if exists)"; ${K} get pods -n "${NS}" -o wide 2>&1 || true; ${K} get svc -n "${NS}" 2>&1 || true; echo
  } > "${SNAPSHOT}" 2>&1 || true
}

collect_failed_events() {
  # Requested data collection
  ${K} get events -n "${NS}" --sort-by='.metadata.creationTimestamp' 2>&1 | grep -i failed > "${EVENTS_FAILED}" || true
}

collect_support_bundle() {
  # Official Kasten support bundle generator
  ./scripts/collect-support.sh "${NS}" "${OUTDIR}" "${TS}" >/dev/null 2>&1 || true
}

write_next_steps() {
  : > "${NEXT_STEPS}"

  # Minimal, high-signal heuristics based on primer output patterns.
  if grep -qi "Unable to find jq" "${PRE_LOG}"; then
    echo "NEXT: install jq on the machine running preflight (primer requires it)." >> "${NEXT_STEPS}"
  fi

  if grep -qi "Kasten Helm repo.*not.*found" "${PRE_LOG}"; then
    echo "NEXT: helm repo add kasten https://charts.kasten.io && helm repo update" >> "${NEXT_STEPS}"
  fi

  if grep -qi "Preflight checks failed" "${PRE_LOG}"; then
    echo "NEXT: primer failed. Review ${PRE_LOG} and attach ${OUTDIR}/support-${TS}.tar.gz (if created) for troubleshooting." >> "${NEXT_STEPS}"
  fi

  if grep -qi "Not a supported CSI driver" "${PRE_LOG}"; then
    echo "NEXT: CSI snapshot checker indicates driver issue. Confirm VolumeSnapshotClass and annotate the correct VSC: kubectl annotate volumesnapshotclass <VSC> k10.kasten.io/is-snapshot-class=true" >> "${NEXT_STEPS}"
    echo "NEXT: rerun primer with explicit storage class: k10_primer.sh | bash /dev/stdin csi -s <STORAGE_CLASS>" >> "${NEXT_STEPS}"
  fi

  # fsGroupPolicy is a strong signal for ownership/permission behavior
  if ${K} get csidriver -o yaml 2>/dev/null | grep -q "fsGroupPolicy: None"; then
    echo "NEXT: CSI driver reports fsGroupPolicy: None (ownership will not be adjusted). Expect permission issues; consider runAsUser/fsGroup tuning or driver configuration." >> "${NEXT_STEPS}"
  fi

  # If no next steps were detected
  if [[ ! -s "${NEXT_STEPS}" ]]; then
    echo "NEXT: no known failure signature detected. Review ${PRE_LOG} and collected artifacts in ${LOGDIR}." >> "${NEXT_STEPS}"
  fi
}

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

main() {
  helm repo add kasten https://charts.kasten.io/ 2>/dev/null || true
  helm repo update >/dev/null

  info "Running Kasten preflight (k10_primer.sh)" 
  if ! run_kasten_primer; then
    err "Preflight FAILED. Collecting troubleshooting data..."
    collect_basics
    collect_failed_events
    collect_support_bundle
    write_next_steps

    err "Preflight artifacts:"
    err "  - ${PRE_LOG}"
    err "  - ${SNAPSHOT}"
    err "  - ${EVENTS_FAILED}"
    err "  - ${NEXT_STEPS}"
    err "(Optional) ${OUTDIR}/support-${TS}.tar.gz"

    exit 1
  fi

  info "Preflight PASSED. Proceeding with install."

  helm install k10 kasten/k10 \
    -f base-values.yaml \
    -f "overlays/${ENV_OVERLAY}" \
    -n "${NS}" \
    --create-namespace

  info "Install complete. Preflight log: ${PRE_LOG}"
}

main "$@"

