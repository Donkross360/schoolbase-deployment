#!/usr/bin/env bash
set -euo pipefail

backup=${1:-}
[[ -n "$backup" && -f "$backup" ]] || { echo "Usage: $0 path/to/backup.sql.gz" >&2; exit 2; }

: "${POSTGRES_ADMIN_USER:?set POSTGRES_ADMIN_USER}"
: "${POSTGRES_ADMIN_PASSWORD:?set POSTGRES_ADMIN_PASSWORD}"
: "${DB_NAME:?set DB_NAME}"
: "${DB_USER:?set DB_USER}"

network=${SCHOOLBASE_NETWORK:-schoolbase-shared}
postgres_image=${POSTGRES_CLIENT_IMAGE:-postgres:16.15-alpine}
expected_tables=${EXPECTED_TABLE_COUNT:-59}

[[ "$DB_NAME" =~ ^[a-z][a-z0-9_]{1,62}$ ]] || { echo "Unsafe DB_NAME" >&2; exit 1; }
[[ "$DB_USER" =~ ^[a-z][a-z0-9_]{1,62}$ ]] || { echo "Unsafe DB_USER" >&2; exit 1; }

gzip -t "$backup"
docker network inspect "$network" >/dev/null

table_count=$(docker run --rm --network "$network" \
  -e PGPASSWORD="$POSTGRES_ADMIN_PASSWORD" \
  "$postgres_image" \
  psql -h postgres -U "$POSTGRES_ADMIN_USER" -d "$DB_NAME" -Atqc \
  "SELECT count(*) FROM pg_tables WHERE schemaname = 'public'")

if [[ "$table_count" != "0" ]]; then
  echo "Refusing restore: $DB_NAME already contains $table_count public tables." >&2
  exit 1
fi

gzip -cd "$backup" \
  | sed -E "s/OWNER TO postgres;/OWNER TO ${DB_USER};/g" \
  | docker run --rm -i --network "$network" \
      -e PGPASSWORD="$POSTGRES_ADMIN_PASSWORD" \
      "$postgres_image" \
      psql -h postgres -U "$POSTGRES_ADMIN_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1

restored_tables=$(docker run --rm --network "$network" \
  -e PGPASSWORD="$POSTGRES_ADMIN_PASSWORD" \
  "$postgres_image" \
  psql -h postgres -U "$POSTGRES_ADMIN_USER" -d "$DB_NAME" -Atqc \
  "SELECT count(*) FROM pg_tables WHERE schemaname = 'public'")

if (( restored_tables < expected_tables )); then
  echo "Restore verification failed: expected at least $expected_tables tables, found $restored_tables." >&2
  exit 1
fi

echo "Restored $backup into $DB_NAME and verified $restored_tables public tables."

