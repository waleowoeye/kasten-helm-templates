#!/bin/bash
set -euo pipefail

ENV=${1:-values-multicluster.yaml}

echo "🚀 Upgrading Kasten with ${ENV}"

helm upgrade --install k10 kasten/k10 \
  -f base-values.yaml \
  -f overlays/${ENV} \
  -n kasten-io \
  --create-namespace

echo "✅ Upgrade complete"

