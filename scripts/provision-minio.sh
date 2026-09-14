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
    bucket=demo
    access_key=${DEMO_MINIO_ACCESS_KEY:?set DEMO_MINIO_ACCESS_KEY}
    secret_key=${DEMO_MINIO_SECRET_KEY:?set DEMO_MINIO_SECRET_KEY}
    ;;
  stpaul)
    bucket=stpaul
    access_key=${STPAUL_MINIO_ACCESS_KEY:?set STPAUL_MINIO_ACCESS_KEY}
    secret_key=${STPAUL_MINIO_SECRET_KEY:?set STPAUL_MINIO_SECRET_KEY}
    ;;
  *)
    echo "Usage: $0 demo|stpaul" >&2
    exit 2
    ;;
esac

public_read=${MINIO_BUCKET_PUBLIC_READ:-true}
case "$public_read" in
  true|false) ;;
  *) echo "MINIO_BUCKET_PUBLIC_READ must be true or false" >&2; exit 1 ;;
esac

case "$access_key" in
  [A-Za-z0-9]* ) ;;
  * ) echo "Invalid MinIO access key" >&2; exit 1 ;;
esac
case "$access_key" in
  *[!A-Za-z0-9._-]* ) echo "Invalid MinIO access key" >&2; exit 1 ;;
esac

alias_name=schoolbase-root
mc alias set "$alias_name" http://127.0.0.1:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
mc mb --ignore-existing "$alias_name/$bucket"

policy_file=$(mktemp)
trap 'rm -f "$policy_file"' EXIT
cat >"$policy_file" <<EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:GetBucketLocation","s3:ListBucket"],"Resource":["arn:aws:s3:::$bucket"]},{"Effect":"Allow","Action":["s3:GetObject","s3:PutObject","s3:DeleteObject"],"Resource":["arn:aws:s3:::$bucket/*"]}]}
EOF

policy_name=school-$bucket
mc admin policy create "$alias_name" "$policy_name" "$policy_file" >/dev/null
if ! mc admin user info "$alias_name" "$access_key" >/dev/null 2>&1; then
  mc admin user add "$alias_name" "$access_key" "$secret_key" >/dev/null
elif [ "$mode" = rotate ]; then
  mc admin user add "$alias_name" "$access_key" "$secret_key" >/dev/null
fi
mc admin policy attach "$alias_name" "$policy_name" --user "$access_key" >/dev/null

if [ "$public_read" = true ]; then
  mc anonymous set download "$alias_name/$bucket" >/dev/null
else
  mc anonymous set none "$alias_name/$bucket" >/dev/null
fi

mc alias set schoolbase-check http://127.0.0.1:9000 "$access_key" "$secret_key" >/dev/null
mc ls "schoolbase-check/$bucket" >/dev/null

echo "MinIO resources for $school are ready ($mode mode)."
