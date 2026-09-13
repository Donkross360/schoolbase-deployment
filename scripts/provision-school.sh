#!/usr/bin/env bash
set -euo pipefail

: "${POSTGRES_ADMIN_USER:?set POSTGRES_ADMIN_USER}"
: "${POSTGRES_ADMIN_PASSWORD:?set POSTGRES_ADMIN_PASSWORD}"
: "${MINIO_ROOT_USER:?set MINIO_ROOT_USER}"
: "${MINIO_ROOT_PASSWORD:?set MINIO_ROOT_PASSWORD}"
: "${DB_NAME:?set DB_NAME}"
: "${DB_USER:?set DB_USER}"
: "${DB_PASS:?set DB_PASS}"
: "${MINIO_BUCKET_NAME:?set MINIO_BUCKET_NAME}"
: "${MINIO_ACCESS_KEY:?set MINIO_ACCESS_KEY}"
: "${MINIO_SECRET_KEY:?set MINIO_SECRET_KEY}"

network=${SCHOOLBASE_NETWORK:-schoolbase-shared}
postgres_image=${POSTGRES_CLIENT_IMAGE:-postgres:16.15-alpine}
minio_client_image=${MINIO_CLIENT_IMAGE:-minio/mc:RELEASE.2025-07-16T15-35-03Z}
public_read=${MINIO_BUCKET_PUBLIC_READ:-true}

[[ "$DB_NAME" =~ ^[a-z][a-z0-9_]{1,62}$ ]] || { echo "Unsafe DB_NAME" >&2; exit 1; }
[[ "$DB_USER" =~ ^[a-z][a-z0-9_]{1,62}$ ]] || { echo "Unsafe DB_USER" >&2; exit 1; }
[[ "$MINIO_BUCKET_NAME" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] || { echo "Invalid MINIO_BUCKET_NAME" >&2; exit 1; }
[[ "$MINIO_ACCESS_KEY" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{2,63}$ ]] || { echo "Invalid MINIO_ACCESS_KEY" >&2; exit 1; }
[[ "$public_read" == "true" || "$public_read" == "false" ]] || { echo "MINIO_BUCKET_PUBLIC_READ must be true or false" >&2; exit 1; }

docker network inspect "$network" >/dev/null

docker run --rm --network "$network" \
  -e PGPASSWORD="$POSTGRES_ADMIN_PASSWORD" \
  -e POSTGRES_ADMIN_USER \
  -e APP_DB_NAME="$DB_NAME" \
  -e APP_DB_USER="$DB_USER" \
  -e APP_DB_PASSWORD="$DB_PASS" \
  "$postgres_image" sh -euc '
    psql -h postgres -U "$POSTGRES_ADMIN_USER" -d postgres \
      -v ON_ERROR_STOP=1 \
      -v app_db="$APP_DB_NAME" \
      -v app_user="$APP_DB_USER" \
      -v app_password="$APP_DB_PASSWORD" <<"SQL"
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'app_user', :'app_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_user')
\gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'app_db', :'app_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'app_db')
\gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', :'app_db', :'app_user')
\gexec
SQL
  '

docker run --rm --network "$network" \
  -e PGPASSWORD="$DB_PASS" \
  "$postgres_image" \
  psql -h postgres -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -c 'SELECT 1' >/dev/null

docker run --rm --network "$network" \
  -e MINIO_ROOT_USER \
  -e MINIO_ROOT_PASSWORD \
  -e MINIO_BUCKET_NAME \
  -e MINIO_ACCESS_KEY \
  -e MINIO_SECRET_KEY \
  -e MINIO_BUCKET_PUBLIC_READ="$public_read" \
  --entrypoint /bin/sh \
  "$minio_client_image" -euc '
    mc alias set root http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
    mc mb --ignore-existing "root/$MINIO_BUCKET_NAME"

    policy_file=$(mktemp)
    trap "rm -f $policy_file" EXIT
    cat >"$policy_file" <<EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:GetBucketLocation","s3:ListBucket"],"Resource":["arn:aws:s3:::$MINIO_BUCKET_NAME"]},{"Effect":"Allow","Action":["s3:GetObject","s3:PutObject","s3:DeleteObject"],"Resource":["arn:aws:s3:::$MINIO_BUCKET_NAME/*"]}]}
EOF
    policy_name="school-$MINIO_BUCKET_NAME"
    mc admin policy create root "$policy_name" "$policy_file" >/dev/null
    if ! mc admin user info root "$MINIO_ACCESS_KEY" >/dev/null 2>&1; then
      mc admin user add root "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" >/dev/null
    fi
    mc admin policy attach root "$policy_name" --user "$MINIO_ACCESS_KEY" >/dev/null

    if [ "$MINIO_BUCKET_PUBLIC_READ" = true ]; then
      mc anonymous set download "root/$MINIO_BUCKET_NAME" >/dev/null
    else
      mc anonymous set none "root/$MINIO_BUCKET_NAME" >/dev/null
    fi

    mc alias set school http://minio:9000 "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" >/dev/null
    mc ls "school/$MINIO_BUCKET_NAME" >/dev/null
  '

echo "School resources are provisioned and accessible with their restricted credentials."
