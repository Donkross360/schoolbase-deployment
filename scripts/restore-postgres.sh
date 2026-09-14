#!/bin/sh
set -eu

school=${1:-}
case "$school" in
  demo)
    db_name=sb_demo
    db_user=${DEMO_DB_USER:?set DEMO_DB_USER}
    object=sb_demo.sql.gz
    ;;
  stpaul)
    db_name=sb_stpaul
    db_user=${STPAUL_DB_USER:?set STPAUL_DB_USER}
    object=sb_stpaul.sql.gz
    ;;
  *) echo "Usage: $0 demo|stpaul" >&2; exit 2 ;;
esac

: "${RESTORE_MINIO_ACCESS_KEY:?set RESTORE_MINIO_ACCESS_KEY}"
: "${RESTORE_MINIO_SECRET_KEY:?set RESTORE_MINIO_SECRET_KEY}"
expected_tables=${EXPECTED_TABLE_COUNT:-59}
backup=/tmp/$object
restore_target=schoolbase-restore/schoolbase-imports/$object

mc alias set schoolbase-restore http://minio:9000 \
  "$RESTORE_MINIO_ACCESS_KEY" "$RESTORE_MINIO_SECRET_KEY" >/dev/null
mc cp "$restore_target" "$backup" >/dev/null
gzip -t "$backup"

export PGPASSWORD=${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is unavailable}
table_count=$(psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$db_name" -Atqc \
  "SELECT count(*) FROM pg_tables WHERE schemaname = 'public'")
if [ "$table_count" != 0 ]; then
  echo "Refusing restore: $db_name already contains $table_count public tables." >&2
  exit 1
fi

gzip -cd "$backup" \
  | sed "s/OWNER TO postgres;/OWNER TO $db_user;/g" \
  | psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$db_name" -v ON_ERROR_STOP=1

restored_tables=$(psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$db_name" -Atqc \
  "SELECT count(*) FROM pg_tables WHERE schemaname = 'public'")
if [ "$restored_tables" -lt "$expected_tables" ]; then
  echo "Restore verification failed: expected at least $expected_tables tables, found $restored_tables." >&2
  exit 1
fi

mc rm "$restore_target" >/dev/null
rm -f "$backup"
echo "Restored $object into $db_name, verified $restored_tables tables, and removed the transfer copy."
