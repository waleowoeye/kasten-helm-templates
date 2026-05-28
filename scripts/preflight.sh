#!/usr/bin/env bash
set -euo pipefail

NS="kasten-io"
HOST="${1:-k10.example.com}"
PATH="/k10/"

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
err()  { echo "[ERROR] $*"; exit 1; }

# 1) Kubernetes access
kubectl version --short >/dev/null 2>&1 || err "kubectl not configured"
helm version >/dev/null 2>&1 || warn "helm not found in PATH"

# 2) Storage checks
info "Checking default StorageClass"
SC=$(kubectl get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' || true)
[[ -z "$SC" ]] && warn "No default StorageClass found" || info "Default SC: $SC"

info "Checking volume expansion support"
EXPAND=$(kubectl get sc "$SC" -o jsonpath='{.allowVolumeExpansion}' 2>/dev/null || echo "unknown")
info "allowVolumeExpansion: ${EXPAND}"

# 3) Namespace
kubectl get ns "$NS" >/dev/null 2>&1 || info "Namespace $NS will be created during install"

# 4) DNS resolution
touch /tmp/k10_preflight_dns
if getent hosts "$HOST" >/dev/null 2>&1; then
  info "DNS resolves: $HOST"
else
  warn "DNS does not resolve: $HOST"
fi

# 5) Ingress/Route reachability
URL="https://${HOST}${PATH}"
info "Probing URL: $URL"
if curl -k -s -o /dev/null -w "%{http_code}" "$URL" | grep -E "^(200|302)$" >/dev/null; then
  info "HTTP probe OK (200/302)"
else
  warn "HTTP probe failed for $URL"
fi

# 6) TLS validation (without -k)
info "Validating TLS certificate"
if echo | openssl s_client -connect "${HOST}:443" -servername "$HOST" 2>/dev/null | openssl x509 -noout -subject >/dev/null 2>&1; then
  info "TLS handshake OK"
else
  warn "TLS handshake failed. If using self-signed, ensure CA is trusted or use cacertconfigmap."
fi

# 7) /k10/ path check
info "Checking K10 path"
if curl -s -o /dev/null -w "%{http_code}" "https://${HOST}/k10/" | grep -E "^(200|302)$" >/dev/null; then
  info "/k10/ path OK"
else
  warn "/k10/ path not reachable"
fi

info "Preflight complete"

