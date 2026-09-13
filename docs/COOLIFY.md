# Coolify deployment runbook

## 1. Build the application image

The frontend and backend application corrections must first be committed to
their `feat/runtime-templating` branches.

In the deployment repository, run the **Build SchoolBase image** GitHub Actions
workflow. Select the exact frontend and backend refs. The workflow publishes a
GHCR tag containing both resolved commit SHAs. Record the complete image name;
do not replace it with `latest`.

If the GHCR package is private, add read-only GHCR credentials to Coolify before
creating school resources.

## 2. Configure DNS

Point these records to the Coolify server:

```text
demo.schoolbase.africa
api.demo.schoolbase.africa
stpaul.schoolbase.africa
api.stpaul.schoolbase.africa
files.schoolbase.africa
```

`files.schoolbase.africa` is the browser-facing MinIO API endpoint used for
uploaded images. Backend uploads and deletes still use the private
`http://minio:9000` address.

## 3. Deploy shared infrastructure

Create one Git-based Docker Compose resource in Coolify:

- repository: this deployment repository;
- branch: the reviewed deployment branch;
- base directory: `/`;
- Compose location: `/compose.infrastructure.yml`;
- environment variables: values based on `config/infrastructure.env.example`.

Configure only `https://files.schoolbase.africa:9000` as a MinIO domain. Do not
assign a domain to PostgreSQL or the MinIO console on port `9001`. Do not add
host port mappings.

Deploy and wait for PostgreSQL and MinIO to become healthy. Confirm that Docker
network `schoolbase-shared` and volumes `schoolbase-postgres-data` and
`schoolbase-minio-data` exist.

## 4. Provision each school

From a trusted server terminal with Docker access, load the infrastructure
administrator variables and the school's variables, then run:

```bash
./scripts/validate-config.sh infrastructure
./scripts/validate-config.sh school
./scripts/provision-school.sh
```

Provision Demo with database `sb_demo`, database role `sb_demo_app`, bucket
`demo`, and a Demo-only MinIO access key. Provision St Paul with database
`sb_stpaul`, database role `sb_stpaul_app`, bucket `stpaul`, and a St Paul-only
MinIO access key.

The current upload feature returns persistent image URLs, so set
`MINIO_BUCKET_PUBLIC_READ=true`. This grants anonymous object downloads only;
database and MinIO write credentials remain school-specific. Do not use this
mechanism later for private documents.

Rerunning provisioning keeps existing data and credentials. If supplied
credentials do not match an existing role or user, verification fails instead
of changing the credential silently.

## 5. Restore the databases

Provision both schools before restoring. Make the two backup files available on
the server, then load the matching administrator and school variables and run:

```bash
DB_NAME=sb_demo DB_USER=sb_demo_app ./scripts/restore-school.sh /path/to/sb_demo.sql.gz
DB_NAME=sb_stpaul DB_USER=sb_stpaul_app ./scripts/restore-school.sh /path/to/sb_stpaul.sql.gz
```

The script validates gzip integrity and refuses to restore into a database that
already contains public tables. It changes object ownership from the dump's old
`postgres` owner to the restricted school role and verifies the restored table
count.

## 6. Deploy Demo

Create a separate Git-based Docker Compose application using
`/compose.school.yml`. Enter values based on `config/school.env.example`, using
Demo's credentials and immutable image tag.

On the `app` service, configure both domains with their target ports:

```text
https://demo.schoolbase.africa:3000
https://api.demo.schoolbase.africa:3008
```

The public request still uses HTTPS port `443`; the suffix tells Coolify which
internal container port to target. The Compose file joins the existing
`schoolbase-shared` network and does not publish either application port.

Deploy Demo and run:

```bash
FRONTEND_URL=https://demo.schoolbase.africa \
API_PUBLIC_URL=https://api.demo.schoolbase.africa \
./scripts/verify-school.sh
```

Verify login, restored records, a new image upload, and the resulting
`files.schoolbase.africa/demo/...` URL before continuing.

## 7. Deploy St Paul

Create another Coolify application from the same Compose file and immutable
image. Use St Paul's environment values and configure:

```text
https://stpaul.schoolbase.africa:3000
https://api.stpaul.schoolbase.africa:3008
```

Deploy and run the verification script with the St Paul URLs. Confirm Demo
remains available during the St Paul deployment.

## 8. Coolify networking setting

The Compose definitions explicitly use the external `schoolbase-shared`
network. Do not enable Raw Compose Deployment. Coolify must remain responsible
for adding proxy routing and joining its proxy to public services. If Coolify
reports that the external network is missing, deploy the infrastructure resource
first rather than creating another network with a different name.

