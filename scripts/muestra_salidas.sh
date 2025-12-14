#!/usr/bin/env bash
set -euo pipefail
NS="${1:-default}"
echo "Artifacts "; ls -lah artifacts || true
echo; echo "SBOMs "; ls -1 artifacts/*-sbom.json 2>/dev/null || echo "(no hay)"
echo; echo "SCA (SARIF) "; ls -1 artifacts/*-grype.sarif 2>/dev/null || echo "(no hay)"
echo; echo "Manifests "; ls -1 artifacts/*.yaml 2>/dev/null || echo "(no hay)"
echo; echo "Deployments "; kubectl get deploy -n "$NS" -o wide || true
echo; echo "Services "; kubectl get svc -n "$NS" || true
echo; echo "EndpointSlices "; kubectl get endpointslices.discovery.k8s.io -n "$NS" 2>/dev/null | egrep 'order-service|user-service' || true
