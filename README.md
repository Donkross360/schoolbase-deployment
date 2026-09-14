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

The old `docker-compose.yml` and `deploy.sh` describe the previous host-managed
deployment. Do not run `deploy.sh` on a Coolify server: Coolify owns Docker,
domain routing, and TLS configuration.

## Current schools

| School | Frontend | API | Database | MinIO bucket |
| --- | --- | --- | --- | --- |
| Demo | `demo.schoolbase.africa` | `api.demo.schoolbase.africa` | `sb_demo` | `demo` |
| St Paul | `stpaul.schoolbase.africa` | `api.stpaul.schoolbase.africa` | `sb_stpaul` | `stpaul` |

Read `docs/COOLIFY.md` before deploying or restoring data.
