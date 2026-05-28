#!/usr/bin/env bash
set -euo pipefail

# --- user-tunable ---
NS="${K10_NAMESPACE:-kasten-io}"
RELEASE="${K10_RELEASE:-k10}"
HOST="${1:-${K10_HOST:-}}"          # optional: k10.example.com
PATH_PREFIX="${K10_PATH:-/k10/}"
STORAGE_CLASS="${K10_STORAGE_CLASS:-}"  # optional: used for CSI checker
OUTDIR="${K10_OUTDIR:-./artifacts}"
# ---

mkdir -p "$OUTDIR"
TS="$(date +%Y%m%d-%H%M%S)"
LOG="$OUTDIR/preflight-${TS}.log"
SUMMARY="$OUTDIR/preflight-${TS}.summary"

info() { echo "[INFO] $*" | tee -a "$LOG"; }
warn() { echo "[WARN] $*" | tee -a "$LOG"; }
err()  { echo "[ERROR] $*" | tee -a "$LOG"; }

need() { command -v "$1" >/dev/null 2>&1 || { err "Missing required tool: $1"; exit 2; }; }

need kubectl
need curl
need bash

# Optional tools
command -v helm >/dev/null 2>&1 || warn "helm not found (only needed for install/upgrade)"
command -v openssl >/dev/null 2>&1 || warn "openssl not found (TLS checks will be limited)"

# --- helper: capture basics ---
collect_basics() {
  info "Collecting baseline cluster info"
  {
    echo "# kubectl version"; kubectl version --short 2>&1 || true; echo
    echo "# contexts"; kubectl config current-context 2>&1 || true; echo
    echo "# nodes"; kubectl get nodes -o wide 2>&1 || true; echo
    echo "# storageclasses"; kubectl get sc 2>&1 || true; echo
    echo "# csidrivers"; kubectl get csidriver 2>&1 || true; echo
    echo "# volumesnapshotclasses"; kubectl get volumesnapshotclass 2>&1 || true; echo
    echo "# ingress/route (best-effort)";
    kubectl get ingress -A 2>&1 || true
    kubectl get route -A 2>&1 || true
  } >> "$LOG"
}

# --- helper: determine default StorageClass ---
get_default_sc() {
  kubectl get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null || true
}

# --- helper: suggest next step based on common outputs ---
suggest_next_steps() {
  info "Creating next-steps summary"

  DEFAULT_SC="$(get_default_sc)"

  {
    echo "Preflight summary: ${TS}"
    echo "Namespace: ${NS}"
    echo "Release: ${RELEASE}"
    echo "Host: ${HOST:-<not provided>}"
    echo "StorageClass (provided): ${STORAGE_CLASS:-<not provided>}"
    echo "Default StorageClass: ${DEFAULT_SC:-<none>}"
    echo

    if [[ -z "$DEFAULT_SC" ]]; then
      echo "NEXT: No default StorageClass detected. Set a performant SC as default OR set K10 storage class explicitly (e.g. global.persistence.storageClass)."
    fi

    # fsGroupPolicy quick hint (if CSI drivers exist)
    if kubectl get csidriver >/dev/null 2>&1; then
      FSGP=$(kubectl get csidriver -o yaml 2>/dev/null | grep -E "fsGroupPolicy:" | head -n 1 || true)
      if echo "$FSGP" | grep -q "None"; then
        echo "NEXT: CSI driver reports fsGroupPolicy: None. Expect permission/ownership issues. Consider driver config change or run-as-user/fsGroup adjustments."
      fi
    fi

    # TLS hint
    if [[ -n "${HOST}" ]] && command -v openssl >/dev/null 2>&1; then
      if ! echo | openssl s_client -connect "${HOST}:443" -servername "$HOST" 2>/dev/null | openssl x509 -noout -subject >/dev/null 2>&1; then
        echo "NEXT: TLS handshake failed for ${HOST}:443. If using self-signed, add CA via cacertconfigmap (preferred) or use insecureCA for POC." 
      fi
    fi

    # Path hint
    if [[ -n "${HOST}" ]]; then
      CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "https://${HOST}${PATH_PREFIX}" || true)
      if [[ "$CODE" != "200" && "$CODE" != "302" ]]; then
        echo "NEXT: ${PATH_PREFIX} not reachable (HTTP ${CODE}). Verify ingress/route and that URL uses /k10/ (not /k10/#/)."
      fi
    fi

  } | tee "$SUMMARY" >> "$LOG"
}

# --- run official Kasten preflight (k10_primer.sh) ---
run_kasten_primer() {
  info "Running Kasten preflight (k10_primer.sh)"

  # Use latest primer from docs 'latest' path. This downloads and runs a job in-cluster.
  # You can pin the version by replacing 'latest' with a versioned downloads path.
  PRIMER_URL="https://docs.kasten.io/downloads/8.5.9/tools/k10_primer.sh"

  set +e
  if [[ -n "$STORAGE_CLASS" ]]; then
    curl -s "$PRIMER_URL" | bash /dev/stdin csi -s "$STORAGE_CLASS" 2>&1 | tee -a "$LOG"
    RC=${PIPESTATUS[2]}
  else
    curl -s "$PRIMER_URL" | bash 2>&1 | tee -a "$LOG"
    RC=${PIPESTATUS[2]}
  fi
  set -e

  return $RC
}

# --- auto-collect on failure ---
collect_support_bundle() {
  info "Preflight failed. Collecting troubleshooting bundle..."
  ./scripts/collect-support.sh "$NS" "$OUTDIR" "$TS" >> "$LOG" 2>&1 || true
}

main() {
  collect_basics

  if run_kasten_primer; then
    info "Kasten primer: PASS"
    echo "STATUS=PASS" | tee -a "$SUMMARY" >> "$LOG"
    suggest_next_steps
    exit 0
  else
    warn "Kasten primer: FAIL"
    echo "STATUS=FAIL" | tee -a "$SUMMARY" >> "$LOG"
    suggest_next_steps
    collect_support_bundle
    err "Preflight failed. See: $SUMMARY and artifacts in $OUTDIR"
    exit 1
  fi
}

main "$@"

