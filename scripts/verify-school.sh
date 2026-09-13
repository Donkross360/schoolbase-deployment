#!/usr/bin/env bash
set -euo pipefail

: "${FRONTEND_URL:?set FRONTEND_URL}"
: "${API_PUBLIC_URL:?set API_PUBLIC_URL}"

frontend_url=${FRONTEND_URL%/}
api_url=${API_PUBLIC_URL%/}
attempts=${VERIFY_ATTEMPTS:-12}
delay=${VERIFY_DELAY_SECONDS:-5}

check() {
  local name=$1 url=$2
  local attempt
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if curl --fail --silent --show-error --location --max-time 15 "$url" >/dev/null; then
      echo "$name check passed: $url"
      return 0
    fi
    if (( attempt < attempts )); then
      sleep "$delay"
    fi
  done
  echo "$name check failed after $attempts attempts: $url" >&2
  return 1
}

check "API liveness" "$api_url/api/v1/health/live"
check "API readiness" "$api_url/api/v1/health/ready"
check "Frontend" "$frontend_url/"

echo "Public SchoolBase checks passed."

