#!/bin/sh
set -eu

school=${1:-}
case "$school" in
  demo) object=sb_demo.sql.gz ;;
  stpaul) object=sb_stpaul.sql.gz ;;
  *) echo "Usage: $0 demo|stpaul" >&2; exit 2 ;;
esac

: "${RESTORE_MINIO_ACCESS_KEY:?set RESTORE_MINIO_ACCESS_KEY}"
: "${RESTORE_MINIO_SECRET_KEY:?set RESTORE_MINIO_SECRET_KEY}"

root_alias=schoolbase-root
restore_alias=schoolbase-restore
bucket=schoolbase-imports
policy=schoolbase-imports

mc alias set "$root_alias" http://127.0.0.1:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
mc mb --ignore-existing "$root_alias/$bucket" >/dev/null
mc anonymous set none "$root_alias/$bucket" >/dev/null

policy_file=$(mktemp)
trap 'rm -f "$policy_file"' EXIT
cat >"$policy_file" <<EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:GetBucketLocation","s3:ListBucket"],"Resource":["arn:aws:s3:::$bucket"]},{"Effect":"Allow","Action":["s3:GetObject","s3:PutObject","s3:DeleteObject"],"Resource":["arn:aws:s3:::$bucket/*"]}]}
EOF
mc admin policy create "$root_alias" "$policy" "$policy_file" >/dev/null
if ! mc admin user info "$root_alias" "$RESTORE_MINIO_ACCESS_KEY" >/dev/null 2>&1; then
  mc admin user add "$root_alias" "$RESTORE_MINIO_ACCESS_KEY" "$RESTORE_MINIO_SECRET_KEY" >/dev/null
fi
mc admin policy attach "$root_alias" "$policy" --user "$RESTORE_MINIO_ACCESS_KEY" >/dev/null
mc alias set "$restore_alias" http://127.0.0.1:9000 \
  "$RESTORE_MINIO_ACCESS_KEY" "$RESTORE_MINIO_SECRET_KEY" >/dev/null

echo "Use the upload command below within one hour:"
mc share upload --expire 1h "$restore_alias/$bucket/$object"
