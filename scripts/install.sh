#!/bin/bash

ENV=${1:-values-multicluster.yaml}

helm upgrade --install k10 kasten/k10 \
  -f base-values.yaml \
  -f overlays/$ENV \
  -n kasten-io \
  --create-namespace
