#!/usr/bin/env bash
# .git/hooks/pre-push (ejemplo): bloquea pushes sin tag inmutable o con vulnerabilidades altas/críticas
set -euo pipefail
SERVICE="${SERVICE:-order-service}"
SCAN_FAIL_SEVERITY="${SCAN_FAIL_SEVERITY:-high}"
echo "[pre-push] Secure build gate para $SERVICE"
make secure-build SERVICE="$SERVICE" SCAN_FAIL_SEVERITY="$SCAN_FAIL_SEVERITY"
