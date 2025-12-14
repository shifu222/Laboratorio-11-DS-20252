#!/usr/bin/env bash
set -euo pipefail

SERVICE="${1:-user-service}"
PORT="${2:-8000}"
NS="${3:-default}"

echo "[i] smoke: $SERVICE/$NS -> http://127.0.0.1:${PORT}"

# Busca un pod del deployment
POD="$(kubectl -n "$NS" get pods -l app="$SERVICE" -o jsonpath='{.items[0].metadata.name}')"

# Port-forward en background
kubectl -n "$NS" port-forward "pod/${POD}" "${PORT}:${PORT}" >/tmp/pf_${SERVICE}.log 2>&1 &
PF_PID=$!
sleep 1

# Curl health (primero /health, si falla usa /)
set +e
curl -fsS "http://127.0.0.1:${PORT}/health" || curl -fsS "http://127.0.0.1:${PORT}/"
RC=$?
set -e

kill $PF_PID >/dev/null 2>&1 || true
wait $PF_PID 2>/dev/null || true

if [ $RC -eq 0 ]; then
  echo "[OK] SMOKE $SERVICE -> 200"
else
  echo "[!] SMOKE $SERVICE FALLÓ"
  exit 1
fi
