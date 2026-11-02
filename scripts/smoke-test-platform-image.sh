#!/usr/bin/env bash
set -euo pipefail

image=${1:?Usage: smoke-test-platform-image.sh IMAGE}
network="platform-smoke-${GITHUB_RUN_ID:-local}-$$"
database="${network}-db"
api="${network}-api"
password=platform_smoke_only

cleanup() {
  status=$?
  if (( status != 0 )); then
    docker logs "$database" 2>/dev/null || true
    docker logs "$api" 2>/dev/null || true
  fi
  docker rm -f "$api" "$database" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker network create "$network" >/dev/null
docker run -d --name "$database" --network "$network" \
  -e POSTGRES_DB=platform_smoke \
  -e POSTGRES_USER=platform_smoke \
  -e "POSTGRES_PASSWORD=$password" \
  postgres:16-alpine >/dev/null

ready=false
for _ in {1..60}; do
  if docker exec "$database" pg_isready -U platform_smoke -d platform_smoke >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  echo 'Disposable PostgreSQL did not become ready' >&2
  exit 1
fi

docker run -d --name "$api" --network "$network" \
  -p 127.0.0.1::3010 \
  -e "DATABASE_URL=postgresql://platform_smoke:${password}@${database}:5432/platform_smoke" \
  -e PROBES_ENABLED=false -e ALERTS_ENABLED=false \
  "$image" >/dev/null

port=$(docker port "$api" 3010/tcp | sed -n 's/^127\.0\.0\.1:\([0-9][0-9]*\)$/\1/p')
if [[ -z "$port" ]]; then
  echo 'Platform API has no localhost port mapping' >&2
  exit 1
fi

ready=false
for _ in {1..90}; do
  if curl --fail --silent "http://127.0.0.1:${port}/health/live" | grep -q '"status":"ok"' \
    && curl --fail --silent "http://127.0.0.1:${port}/health/ready" | grep -q '"status":"ok"'; then
    ready=true
    break
  fi
  if [[ "$(docker inspect -f '{{.State.Running}}' "$api")" != true ]]; then
    echo 'Platform API exited during startup' >&2
    exit 1
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  echo 'Platform API health checks did not become ready' >&2
  exit 1
fi

count=$(docker exec "$database" psql -U platform_smoke -d platform_smoke -Atqc \
  'SELECT count(*) FROM platform_schema_migrations')
if ! [[ "$count" =~ ^[1-9][0-9]*$ ]]; then
  echo 'Platform API started without recorded database migrations' >&2
  exit 1
fi

echo "Platform API started, migrated ${count} files, and passed live/ready checks"
