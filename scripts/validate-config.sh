#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 infrastructure|school [env-file]" >&2
  exit 2
}

mode=${1:-}
env_file=${2:-}
[[ "$mode" == "infrastructure" || "$mode" == "school" ]] || usage

if [[ -n "$env_file" ]]; then
  [[ -f "$env_file" ]] || { echo "Environment file not found: $env_file" >&2; exit 1; }
  set -a
  # shellcheck disable=SC1090
  . "$env_file"
  set +a
fi

errors=0

fail() {
  echo "ERROR: $*" >&2
  errors=$((errors + 1))
}

require_value() {
  local name=$1 value=${!1:-}
  [[ -n "$value" ]] || fail "$name is required"
  [[ "$value" != *replace-with* && "$value" != *change-me* ]] || fail "$name still contains a placeholder"
}

require_secret() {
  local name=$1 value=${!1:-}
  require_value "$name"
  (( ${#value} >= 24 )) || fail "$name must contain at least 24 characters"
}

if [[ "$mode" == "infrastructure" ]]; then
  require_value POSTGRES_ADMIN_USER
  require_secret POSTGRES_ADMIN_PASSWORD
  require_value MINIO_ROOT_USER
  require_secret MINIO_ROOT_PASSWORD
else
  for name in SCHOOLBASE_IMAGE APP_SLUG SCHOOL_NAME FRONTEND_URL API_PUBLIC_URL \
    SUPERADMIN_LOGIN_URL CORS_ORIGINS DB_NAME DB_USER MINIO_BUCKET_NAME \
    MINIO_ACCESS_KEY MINIO_PUBLIC_URL; do
    require_value "$name"
  done

  for name in DB_PASS MINIO_SECRET_KEY JWT_SECRET JWT_REFRESH_SECRET UPLOAD_KEY; do
    require_secret "$name"
  done

  [[ ${APP_SLUG:-} =~ ^[a-z0-9][a-z0-9-]{1,30}$ ]] || fail "APP_SLUG must be a lowercase DNS-safe identifier"
  [[ ${DB_NAME:-} =~ ^[a-z][a-z0-9_]{1,62}$ ]] || fail "DB_NAME must be a safe lowercase PostgreSQL identifier"
  [[ ${DB_USER:-} =~ ^[a-z][a-z0-9_]{1,62}$ ]] || fail "DB_USER must be a safe lowercase PostgreSQL identifier"
  [[ ${MINIO_BUCKET_NAME:-} =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] || fail "MINIO_BUCKET_NAME is not S3-compatible"
  [[ ${FRONTEND_URL:-} =~ ^https://[^/]+$ ]] || fail "FRONTEND_URL must be an HTTPS origin without a path"
  [[ ${API_PUBLIC_URL:-} =~ ^https://[^/]+$ ]] || fail "API_PUBLIC_URL must be an HTTPS origin without a path"
  [[ ${MINIO_PUBLIC_URL:-} =~ ^https://[^/]+$ ]] || fail "MINIO_PUBLIC_URL must be an HTTPS origin without a path"
  [[ ${SUPERADMIN_LOGIN_URL:-} == "${FRONTEND_URL:-}/super-admin/login" ]] || fail "SUPERADMIN_LOGIN_URL must use FRONTEND_URL and /super-admin/login"
  [[ ",${CORS_ORIGINS:-}," == *",${FRONTEND_URL:-},"* ]] || fail "CORS_ORIGINS must include FRONTEND_URL"
  [[ ${SCHOOLBASE_IMAGE:-} != *:latest ]] || fail "SCHOOLBASE_IMAGE must use an immutable tag"
  [[ ${JWT_SECRET:-} != "${JWT_REFRESH_SECRET:-}" ]] || fail "JWT_SECRET and JWT_REFRESH_SECRET must be different"
fi

(( errors == 0 )) || exit 1
echo "$mode configuration is valid"

