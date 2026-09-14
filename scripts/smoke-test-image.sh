#!/usr/bin/env bash

set -Eeuo pipefail

image=${1:?usage: smoke-test-image.sh IMAGE}
run_suffix="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$"
network="schoolbase-smoke-${run_suffix}"
postgres_container="schoolbase-smoke-postgres-${run_suffix}"
minio_container="schoolbase-smoke-minio-${run_suffix}"
app_container="schoolbase-smoke-app-${run_suffix}"

postgres_user=schoolbase_smoke
postgres_password=schoolbase-smoke-postgres-password
database_name=sb_demo
minio_user=schoolbase_smoke
minio_password=schoolbase-smoke-minio-password

cleanup() {
  local exit_code=$?

  if ((exit_code != 0)); then
    docker logs "$app_container" 2>/dev/null || true
    docker logs "$postgres_container" 2>/dev/null || true
    docker logs "$minio_container" 2>/dev/null || true
  fi

  docker rm --force "$app_container" "$postgres_container" "$minio_container" \
    >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
}

trap cleanup EXIT

wait_for_command() {
  local description=$1
  shift

  for _ in $(seq 1 60); do
    if "$@" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  echo "Timed out waiting for ${description}" >&2
  return 1
}

docker network create "$network" >/dev/null

docker run --detach \
  --name "$postgres_container" \
  --network "$network" \
  --network-alias postgres \
  --env "POSTGRES_USER=${postgres_user}" \
  --env "POSTGRES_PASSWORD=${postgres_password}" \
  --env "POSTGRES_DB=${database_name}" \
  postgres:16.15-alpine >/dev/null

docker run --detach \
  --name "$minio_container" \
  --network "$network" \
  --network-alias minio \
  --env "MINIO_ROOT_USER=${minio_user}" \
  --env "MINIO_ROOT_PASSWORD=${minio_password}" \
  quay.io/minio/minio:RELEASE.2025-09-07T16-13-09Z \
  server /data --console-address :9001 >/dev/null

wait_for_command PostgreSQL \
  docker exec "$postgres_container" pg_isready -U "$postgres_user" -d "$database_name"
wait_for_command MinIO docker exec "$minio_container" mc ready local

docker run --detach \
  --name "$app_container" \
  --network "$network" \
  --publish 127.0.0.1:3000:3000 \
  --publish 127.0.0.1:3008:3008 \
  --env NODE_ENV=production \
  --env PORT=3008 \
  --env API_BASE_URL=http://127.0.0.1:3008 \
  --env API_PUBLIC_URL=http://127.0.0.1:3008 \
  --env FRONTEND_URL=http://127.0.0.1:3000 \
  --env SUPERADMIN_LOGIN_URL=http://127.0.0.1:3000/super-admin/login \
  --env CORS_ORIGINS=http://127.0.0.1:3000 \
  --env DATABASE_SETUP_ENABLED=false \
  --env DB_HOST=postgres \
  --env DB_PORT=5432 \
  --env "DB_USER=${postgres_user}" \
  --env "DB_PASS=${postgres_password}" \
  --env "DB_NAME=${database_name}" \
  --env DB_SSL=false \
  --env JWT_SECRET=schoolbase-smoke-access-token-secret \
  --env JWT_REFRESH_SECRET=schoolbase-smoke-refresh-token-secret \
  --env TOKEN_ACCESS_DURATION=1h \
  --env TOKEN_REFRESH_DURATION=7d \
  --env UPLOAD_KEY=schoolbase-smoke-upload-key \
  --env MINIO_ENDPOINT=minio \
  --env MINIO_PORT=9000 \
  --env MINIO_USE_SSL=false \
  --env "MINIO_ACCESS_KEY=${minio_user}" \
  --env "MINIO_SECRET_KEY=${minio_password}" \
  --env MINIO_BUCKET_NAME=demo \
  --env MINIO_PUBLIC_URL=http://minio:9000 \
  --env APP_NAME=SchoolBase \
  --env APP_SLUG=demo \
  --env "SCHOOL_NAME=SchoolBase Demo" \
  --env LOG_LEVEL=info \
  --env HASH_SALT=12 \
  "$image" >/dev/null

wait_for_command "frontend health" curl --fail --silent http://127.0.0.1:3000/
wait_for_command "backend readiness" \
  curl --fail --silent http://127.0.0.1:3008/api/v1/health/ready

runtime_config=$(curl --fail --silent http://127.0.0.1:3000/api/config)
if [[ "$runtime_config" != *'"name":"SchoolBase Demo"'* ]]; then
  echo "Frontend runtime configuration does not contain the Demo school name" >&2
  echo "$runtime_config" >&2
  exit 1
fi

echo "Combined image passed the Demo startup smoke test."
