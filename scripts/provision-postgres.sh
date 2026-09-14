#!/bin/sh
set -eu

school=${1:-}
mode=${2:-ensure}

case "$mode" in
  ensure|rotate) ;;
  *) echo "Usage: $0 demo|stpaul [ensure|rotate]" >&2; exit 2 ;;
esac

case "$school" in
  demo)
    db_name=sb_demo
    db_user=${DEMO_DB_USER:?set DEMO_DB_USER}
    db_password=${DEMO_DB_PASSWORD:?set DEMO_DB_PASSWORD}
    ;;
  stpaul)
    db_name=sb_stpaul
    db_user=${STPAUL_DB_USER:?set STPAUL_DB_USER}
    db_password=${STPAUL_DB_PASSWORD:?set STPAUL_DB_PASSWORD}
    ;;
  *)
    echo "Usage: $0 demo|stpaul" >&2
    exit 2
    ;;
esac

case "$db_user" in
  [a-z]* ) ;;
  * ) echo "Unsafe database user: $db_user" >&2; exit 1 ;;
esac
case "$db_user" in
  *[!a-z0-9_]* ) echo "Unsafe database user: $db_user" >&2; exit 1 ;;
esac

export PGPASSWORD=${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is unavailable}

psql -h 127.0.0.1 -U "$POSTGRES_USER" -d postgres \
  -v ON_ERROR_STOP=1 \
  -v app_db="$db_name" \
  -v app_user="$db_user" \
  -v app_password="$db_password" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'app_user', :'app_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_user')
\gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'app_db', :'app_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'app_db')
\gexec
SELECT format('REVOKE CONNECT ON DATABASE %I FROM PUBLIC', :'app_db')
\gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', :'app_db', :'app_user')
\gexec
SQL

if [ "$mode" = rotate ]; then
  psql -h 127.0.0.1 -U "$POSTGRES_USER" -d postgres \
    -v ON_ERROR_STOP=1 \
    -v app_user="$db_user" \
    -v app_password="$db_password" <<'SQL'
SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'app_user', :'app_password')
WHERE EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_user')
\gexec
SQL
fi

PGPASSWORD=$db_password psql -h postgres -U "$db_user" -d "$db_name" \
  -v ON_ERROR_STOP=1 -c 'SELECT 1' >/dev/null

echo "PostgreSQL resources for $school are ready ($mode mode)."
