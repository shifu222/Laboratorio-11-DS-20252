#!/usr/bin/env bash
# wait-for-http.sh URL [max_tries] [sleep_seconds]
set -euo pipefail
URL="${1:-http://127.0.0.1:8000/health}"
TRIES="${2:-40}"
SLEEP="${3:-2}"
i=0
while true; do
  if curl -fsS "$URL" >/dev/null 2>&1; then
    echo "OK $URL"
    exit 0
  fi
  i=$((i+1))
  if [ "$i" -ge "$TRIES" ]; then
    echo "Timeout esperando $URL" >&2
    exit 1
  fi
  sleep "$SLEEP"
done
