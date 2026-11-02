# Platform pilot on Coolify

This is the deployment path for Phase 1 verification against Demo and St Paul.
The platform service is separate from each school's combined image and from the
public website API. Do not deploy it with school database credentials.

## Resources and images

1. Create a private PostgreSQL database and role dedicated to the platform.
   Keep its volume persistent and back it up. Use the private connection string
   as `DATABASE_URL` on the platform backend only.
2. Create a Dockerfile application from
   `schoolbaseafrica/SchoolBase-Platform-BE` on `main`, using `/Dockerfile` and
   port `3010`. Its startup applies the numbered migrations under an advisory
   lock before starting the API. Check `/health/ready`; a 200 response means
   the database and migration table are reachable.
3. The operator UI is part of `schoolbaseafrica/SchoolBase-Website-FE` on `dev`.
   Its existing `/Dockerfile` builds the site. Set its server-only
   `PLATFORM_API_ORIGIN` to the platform API's HTTPS origin. This URL must be
   reachable from the website container; never use a browser-visible
   `NEXT_PUBLIC_` variable for it.
4. Use `/Dockerfile.collector` from the platform backend repository for
   separate one-shot infrastructure collector jobs. They need no inbound port.
   Override the command for each source: `node scripts/collect-database-size.js`,
   `node scripts/collect-disk-headroom.js`, or
   `node scripts/collect-minio-bucket.js`. Do not run collectors inside a school
   application or give the platform API school database or MinIO credentials.

## Safe initial configuration

Set `NODE_ENV=production`, `PORT=3010`, `DATABASE_URL`,
`PROBES_ENABLED=false`, and `ALERTS_ENABLED=false` on the platform backend.
Mark `DATABASE_URL` secret and runtime-only. Deploy the backend and verify
`/health/ready` before configuring the website operator UI. The API requires
operator authentication for school and metric data; put its HTTPS origin behind
the intended network/access restriction before exposing operator login.

Bootstrap a `platform_admin` through the backend's one-time
`npm run bootstrap:admin` command with the three `PLATFORM_BOOTSTRAP_*`
variables supplied only to that task. The first registry entries for Demo and
St Paul are created through the ordinary authenticated registry API. Do not
copy the disposable `/tmp` test database into production. Record the verified
frontend/API domains, Coolify resource references, and current image tags.

## Verify the pilot sources

Enable one collector at a time. Create its scoped credential through the
platform API, store the returned token only in the matching job, and compare
one received sample with its infrastructure source before scheduling it.
Database size requires a read-only PostgreSQL role tied to the correct school
database; MinIO requires a dedicated metrics scrape token and exact bucket
label; disk headroom requires a verified host or volume mount. Container and
proxy collectors still need read-only source integrations before their values
can be displayed as verified. See the source inventory in
`SchoolBase-Platform-BE/docs/P1_6_SOURCE_INVENTORY.md`.

Keep `ALERTS_ENABLED=false` until source mappings, collection intervals, and
sample values have been checked for both schools. A missing collector is
`unknown`, and synthetic test reports are not production readings. Then enable
the probe and alert schedulers on one platform backend instance, simulate a
warning and a collection failure, and check the dashboard, audit trail, and
acknowledgement flow. Keep Coolify as the deployment and restart control plane.

The platform backend repository currently has no published image workflow;
Coolify builds its Dockerfile directly from the pinned source ref. Record that
ref and the website ref with each pilot deployment.
