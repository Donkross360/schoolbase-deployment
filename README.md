# SchoolBase deployment

This repository deploys multiple isolated SchoolBase schools on one Coolify
server. PostgreSQL and MinIO are shared infrastructure. Each school has its own
application container, database role and database, MinIO user and bucket,
secrets, resource limits, and frontend/API domains.

## Repository layout

| Path | Purpose |
| --- | --- |
| `compose.infrastructure.yml` | Shared PostgreSQL and MinIO stack |
| `Dockerfile.infrastructure-*` | Adds Coolify provisioning commands to the shared service images |
| `compose.school.yml` | Reusable application definition; create one Coolify resource per school |
| `Dockerfile.combined` | Builds the combined Next.js and NestJS image |
| `.github/workflows/build-image.yml` | Builds and publishes an immutable GHCR image |
| `.github/workflows/build-android-apk.yml` | Builds a downloadable Android test APK from a selected mobile ref |
| `config/*.env.example` | Non-secret configuration templates |
| `scripts/validate-config.sh` | Rejects missing, weak, or placeholder configuration |
| `scripts/provision-postgres.sh` | Creates each school's role/database from a Coolify task |
| `scripts/provision-minio.sh` | Creates each school's user/bucket from a Coolify task |
| `scripts/prepare-database-import.sh` | Creates a private, expiring backup upload command |
| `scripts/restore-postgres.sh` | Restores and removes an uploaded backup from a Coolify task |
| `scripts/provision-school.sh` | Host-Docker compatibility wrapper for operators who have server access |
| `scripts/restore-school.sh` | Safely restores a gzip-compressed SQL backup into an empty database |
| `scripts/verify-school.sh` | Checks public frontend and API health routes |
| `docs/DEPLOYMENT_CONTRACT.md` | Runtime, networking, isolation, and health contract |
| `docs/COOLIFY.md` | Deployment runbook |
| `docs/WEBSITE_COOLIFY.md` | Public website frontend/API deployment runbook |

The old `docker-compose.yml` and `deploy.sh` describe the previous host-managed
deployment. Do not run `deploy.sh` on a Coolify server: Coolify owns Docker,
domain routing, and TLS configuration.

## Current schools

| School | Frontend | API | Database | MinIO bucket |
| --- | --- | --- | --- | --- |
| Demo | `demo.schoolbase.africa` | `api.demo.schoolbase.africa` | `sb_demo` | `demo` |
| St Paul | `stpaul.schoolbase.africa` | `api.stpaul.schoolbase.africa` | `sb_stpaul` | `stpaul` |

Read `docs/COOLIFY.md` before deploying or restoring data.

## Build an Android test APK

In this repository's GitHub **Actions** tab, run **Build SchoolBase Android APK**.
Choose a committed mobile source ref and the HTTPS API URL for the school,
ending in `/api/v1`. Until write access to the organization mobile repository
is available, the default mobile source is the `mobile/feat-runtime-templating`
branch in this repository, which mirrors the mobile app commit. To build from
another repository, set `mobile_repository` to its `owner/name` and choose its
branch, tag, or full commit SHA. The workflow checks the app, builds an
installable debug APK, and attaches the APK plus its SHA-256 checksum to the run
for 30 days. The run summary records the mobile commit and backend URL. The
default URL points to the Demo API.

Pushing a `build-*` tag in this deployment repository starts both the combined
image and Android APK workflows using their default source refs. Push the
frontend, backend, and mobile commits before creating that tag.

This APK is signed with a temporary debug key for device testing. Different
workflow runs may require uninstalling the previous APK before installation.
Production distribution needs a stable signing key and a final application ID.
