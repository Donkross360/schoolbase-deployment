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

operator_email=initial-platform-admin@example.invalid
old_password=platform-smoke-original-123
new_password='platform$smoke-recovered-123'

docker exec -e "PLATFORM_BOOTSTRAP_EMAIL=$operator_email" \
  -e PLATFORM_BOOTSTRAP_NAME='Platform Smoke Admin' \
  -e "PLATFORM_BOOTSTRAP_PASSWORD=$old_password" \
  "$api" node scripts/bootstrap-admin.js

if [[ "$(curl --silent --output /dev/null --write-out '%{http_code}' \
  -H 'content-type: application/json' \
  -d '{"email":"initial-platform-admin@example.invalid","password":"platform-smoke-original-123"}' \
  "http://127.0.0.1:${port}/operators/login")" != 201 ]]; then
  echo 'Initial administrator could not log in before recovery' >&2
  exit 1
fi

if docker exec -e PLATFORM_RECOVERY_EMAIL=wrong@example.invalid \
  -e "PLATFORM_RECOVERY_PASSWORD=$new_password" \
  "$api" node scripts/recover-initial-admin.js; then
  echo 'Recovery accepted a different administrator email' >&2
  exit 1
fi

docker exec -e "PLATFORM_RECOVERY_EMAIL=$operator_email" \
  -e "PLATFORM_RECOVERY_PASSWORD=$new_password" \
  "$api" node scripts/recover-initial-admin.js

old_status=$(curl --silent --output /dev/null --write-out '%{http_code}' \
  -H 'content-type: application/json' \
  -d '{"email":"initial-platform-admin@example.invalid","password":"platform-smoke-original-123"}' \
  "http://127.0.0.1:${port}/operators/login")
new_status=$(curl --silent --output /dev/null --write-out '%{http_code}' \
  -H 'content-type: application/json' \
  -d '{"email":"initial-platform-admin@example.invalid","password":"platform$smoke-recovered-123"}' \
  "http://127.0.0.1:${port}/operators/login")
if [[ "$old_status" != 401 || "$new_status" != 201 ]]; then
  echo "Recovery login outcomes were unexpected: old=$old_status new=$new_status" >&2
  exit 1
fi

revoked=$(docker exec "$database" psql -U platform_smoke -d platform_smoke -Atqc \
  'SELECT count(*) FROM platform_sessions WHERE revoked_at IS NOT NULL')
audited=$(docker exec "$database" psql -U platform_smoke -d platform_smoke -Atqc \
  "SELECT count(*) FROM platform_audit_events WHERE action = 'operator.password_recovered'")
if [[ "$revoked" != 1 || "$audited" != 1 ]]; then
  echo "Recovery side effects were unexpected: revoked=$revoked audited=$audited" >&2
  exit 1
fi

docker exec "$database" psql -U platform_smoke -d platform_smoke -q -c \
  "INSERT INTO platform_operators (email, display_name, role, password_hash)
   SELECT 'second@example.invalid', 'Second Operator', 'viewer', password_hash
   FROM platform_operators WHERE email = '$operator_email'" >/dev/null
if docker exec -e "PLATFORM_RECOVERY_EMAIL=$operator_email" \
  -e "PLATFORM_RECOVERY_PASSWORD=$old_password" \
  "$api" node scripts/recover-initial-admin.js; then
  echo 'Recovery accepted a database with multiple operators' >&2
  exit 1
fi
audited=$(docker exec "$database" psql -U platform_smoke -d platform_smoke -Atqc \
  "SELECT count(*) FROM platform_audit_events WHERE action = 'operator.password_recovered'")
if [[ "$audited" != 1 ]]; then
  echo 'Rejected multi-operator recovery wrote an audit event' >&2
  exit 1
fi
echo 'Initial administrator recovery, session revocation, and audit checks passed'
