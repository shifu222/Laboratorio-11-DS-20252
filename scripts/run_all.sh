#!/usr/bin/env bash
set -euo pipefail
SCAN_FAIL_SEVERITY="${SCAN_FAIL_SEVERITY:-high}"
COSIGN_VERIFY="${COSIGN_VERIFY:-0}"
BUILD_IN_MINIKUBE="${BUILD_IN_MINIKUBE:-0}"
USE_REGISTRY="${USE_REGISTRY:-0}"
services=("user-service" "order-service")
make minikube-up
for svc in "${services[@]}"; do
  echo "[$svc]"
  if [[ "$BUILD_IN_MINIKUBE" == "1" && "$USE_REGISTRY" != "1" ]]; then
    make build-in-minikube SERVICE="$svc"
  else
    make build SERVICE="$svc"
    if [[ "$USE_REGISTRY" == "1" ]]; then
      if [[ -z "${IMAGE_REGISTRY:-}" ]]; then echo "Set IMAGE_REGISTRY"; exit 1; fi
      make push SERVICE="$svc"
    fi
  fi
  make sbom SERVICE="$svc"
  make sign SERVICE="$svc" COSIGN_VERIFY="$COSIGN_VERIFY"
  make scan SERVICE="$svc" SCAN_FAIL_SEVERITY="$SCAN_FAIL_SEVERITY"
  make k8s-prepare SERVICE="$svc"
  make k8s-apply SERVICE="$svc"
  make smoke SERVICE="$svc"
  make test SERVICE="$svc" || { make test-down SERVICE="$svc" || true; exit 1; }
  make test-down SERVICE="$svc" || true
done
echo "run_all.sh OK"
