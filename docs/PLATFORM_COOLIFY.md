# SchoolBase platform: Coolify deployment guide

This guide deploys the private operator dashboard at `schoolbase.africa/admin` and prepares a Demo and St Paul pilot. The platform API and database are separate from each school's combined image and from the existing website backend. Keep the existing school and website databases unchanged.

The current code supports registry, availability probes, staff login reports, capacity samples, trends, and dashboard capacity alerts. Container and proxy metric collectors, availability alerts, and alert email are still outstanding. The pilot is complete only after live readings are checked against their sources.

## 0. Record the inputs

Place the platform database and API on the same reachable Coolify destination network. Keep the website frontend in its existing resource; it may be in another project if its container can reach the API HTTPS route. Build the platform API and collector images from `schoolbase-deployment` on `main`; `SchoolBase-Platform-BE` remains the source repository. Record the deployed backend commit and exact images from the workflow summary:

| Resource | Source | Build file | Internal port |
| --- | --- | --- | --- |
| Platform API | Deployment workflow → immutable `schoolbase-platform-api` GHCR image | Backend `/Dockerfile` | 3010 |
| Existing website frontend | `schoolbaseafrica/SchoolBase-Website-FE`, `dev` | `/Dockerfile` | 3000 |
| Each private metric worker | Same deployment workflow → immutable `schoolbase-platform-collector` GHCR image | Backend `/Dockerfile.collector` | none |

Choose an HTTPS API hostname such as `platform-api.schoolbase.africa`. It must be reachable from the website server, school backends, and collectors. Protect the API route with a network, VPN, or IP restriction that admits those callers and the operator setup client. Do not enable Coolify HTTP Basic Authentication on this route: it uses the same `Authorization` header as the API bearer tokens. A gateway requiring extra service-token headers needs client support before use. If the route cannot be protected and reached by all callers, stop before adding school or collector credentials.

## 1. Create platform PostgreSQL

1. In the chosen Coolify project/environment select **New Resource → PostgreSQL**. Create a dedicated platform database and role, for example `schoolbase_platform`. Do not reuse a school or website database.
2. Select the same server and destination network as the API. Keep **public database access off**. Start the database and wait for the healthy state.
3. In its **General** page, copy the **Internal URL** and confirm its database name. Save that URL as the API's secret `DATABASE_URL`. Do not put it in Git, build arguments, or screenshots.
4. In **Backups**, add a recurring schedule and retention, run **Back up now**, and confirm a successful execution. Keep the database volume persistent.

Coolify's [PostgreSQL guide](https://coolify.io/docs/databases/postgresql) describes the private URL. Its [backup guide](https://coolify.io/docs/databases/backups) describes execution history.

## 2. Deploy the platform API

1. In `schoolbase-deployment` on `main`, run **Actions → Build SchoolBase platform images → Run workflow**. Set `platform_ref` to the committed Platform-BE `main` branch or an exact 40-character commit SHA. Wait for both image builds and smoke checks to pass. Copy `PLATFORM_API_DIGEST` and `PLATFORM_COLLECTOR_DIGEST` from the run summary and record `Platform backend` SHA. The summary also gives human-readable commit tags. Use the digest references in Coolify so a repeated build cannot silently change the deployed bytes.
2. In Coolify, select **New Resource → Docker Image** and enter the exact `PLATFORM_API_DIGEST` value. Coolify accepts a full `ghcr.io/...@sha256:...` reference. If the GHCR package is private, configure Coolify registry credentials with package read access before deploying. Do not put the registry token in application environment variables.
3. Set **Ports Exposes** to `3010`. Add the chosen HTTPS domain and verify its DNS/TLS route.
4. Add the following **runtime** variables. Mark `DATABASE_URL` secret:

   ```dotenv
   NODE_ENV=production
   PORT=3010
   DATABASE_URL=<platform PostgreSQL Internal URL>
   PROBES_ENABLED=false
   ALERTS_ENABLED=false
   ```

5. Deploy. The image applies numbered database migrations before starting. Check the GitHub Actions run for the build/source SHA, then Coolify **Deployment Logs** for the image pull and **Runtime Logs** for migration or startup errors.
6. From a client admitted by the API route, request `GET https://<platform-api-host>/health/live` and `GET https://<platform-api-host>/health/ready`. Both should return HTTP 200 with `{"status":"ok"}`. If readiness fails, fix the database connection or migration before continuing.

The API image already migrates on startup under a PostgreSQL advisory lock. Do not configure a second pre-deployment migration command. The workflow publishes images; Coolify pulls them and supplies runtime settings.

## 3. Create the first platform operator

1. Temporarily add `PLATFORM_BOOTSTRAP_EMAIL`, `PLATFORM_BOOTSTRAP_NAME`, and `PLATFORM_BOOTSTRAP_PASSWORD` as **runtime secrets** on the API resource. Use an individual operator email and a password of at least 12 characters. Redeploy so the container receives them.
2. Open the API application's **Terminal** and run `node scripts/bootstrap-admin.js`. Expect `Initial platform administrator created`. Do not type a password into the terminal command. This bootstrap refuses to run once any operator exists.
3. Remove all three bootstrap variables from Coolify and redeploy. Recheck `/health/ready`.
4. From an admitted client, use `POST /operators/login` with that operator's email and password. The response has an eight-hour bearer token. `GET /operators/me` with that token should show `platform_admin`. Keep the token out of logs and documents.

There is no registry creation form in `/admin` yet. The next step uses the authenticated API.

For the API steps below, use a trusted HTTP client with the platform operator token as `Authorization: Bearer <token>`. For example, after entering the token through a hidden prompt in a private shell, a read looks like this:

```bash
read -r -s -p 'Platform token: ' PLATFORM_TOKEN
printf '\n'
curl --fail-with-body -H "Authorization: Bearer ${PLATFORM_TOKEN}" \
  "https://<platform-api-host>/schools"
```

Clear the shell variable with `unset PLATFORM_TOKEN` after setup. Do not paste a token into a saved request collection or a screenshot.

## 4. Register Demo and St Paul once

1. With a platform `operator` or `platform_admin` token, call `GET /schools`. If a school exists, inspect it and update it with `PATCH /schools/:id` plus its current `expected_version`. Do not create a duplicate.
2. For a missing Demo record, send `POST /schools` with `Content-Type: application/json` and this body:

   ```json
   {
     "slug": "demo",
     "display_name": "SchoolBase Demo",
     "frontend_url": "https://demo.schoolbase.africa",
     "api_url": "https://api.demo.schoolbase.africa",
     "lifecycle_state": "active",
     "reason": "Register existing Demo deployment for platform pilot"
   }
   ```

   Save the body as a temporary `demo.json` file, then send it from the admitted setup client:

   ```bash
   curl --fail-with-body -X POST \
     -H "Authorization: Bearer ${PLATFORM_TOKEN}" \
     -H 'Content-Type: application/json' \
     --data-binary @demo.json "https://<platform-api-host>/schools"
   ```

   The file contains no token, but remove it from the setup machine when registration is done.

3. Repeat with slug `stpaul` and its actual frontend/API domains. Read each response and confirm distinct stable IDs. Add `coolify_resource_ref` and `image_tag` only after reading their real values from Coolify. Registry writes do not change a school database or deploy an image.
4. Call `GET /schools` and `GET /operators/audit`. Expect exactly one record per school and an actor/reason for each change.

URL fields must be HTTPS origins without paths or ports. School admin tokens cannot access this API.

## 5. Connect the existing website frontend

1. Open the existing `SchoolBase-Website-FE` resource. Confirm branch `dev`, Dockerfile `/Dockerfile`, and port `3000`. Leave `SchoolBase-Website-BE` unchanged.
2. Add the server-only **runtime** variable `PLATFORM_API_ORIGIN=https://<platform-api-host>`. Use the origin only, with no path or trailing slash. Do not create a `NEXT_PUBLIC_` copy.
3. Redeploy the website frontend. Open `https://schoolbase.africa/admin`. It should redirect to `/admin/login`. Sign in with the platform operator account.
4. The overview should show Demo and St Paul. Uncollected metrics should say unavailable. Open each school detail page and check that one school's samples are not shown under the other.
5. If login reports that the platform is unavailable, check website **Runtime Logs** and verify that the website container can reach the API HTTPS route. A health request from a laptop alone does not prove container reachability.

## 6. Turn on availability and school activity

1. Confirm each registered frontend URL loads and each school API's `GET /api/v1/health/ready` returns its expected ready response.
2. Change `PROBES_ENABLED=true` on **one** platform API instance and redeploy. After two minutes, compare `GET /schools/demo/status` and `GET /schools/stpaul/status` with direct checks. Review source, observed time, result, and HTTP status separately for frontend and backend. Health does not establish deployment state.
3. Create one staff activity credential per school with `POST /schools/demo/credentials` or `/schools/stpaul/credentials` and body `{"reason":"Connect staff login report"}`. Each token is shown once.
4. Put Demo's token only in the Demo combined application's `PLATFORM_SCHOOL_TOKEN`, and St Paul's token only in St Paul's. Set each application's `PLATFORM_ACTIVITY_URL=https://<platform-api-host>/school-signals/staff-login`. Redeploy each school application separately.
5. Within five minutes, inspect each school's platform status. `last_staff_login_at` reflects successful admin/teacher logins; no recorded login is different from an outage. Check each school's runtime logs for repeated report failures.

## 7. Add private metric workers one at a time

Coolify [Scheduled Tasks](https://coolify.io/docs/applications/operations/scheduled-tasks) run commands **inside a running container**. The collector image keeps a private worker alive; the scheduled command runs once and exits. Create a separate **Docker Image** resource for each collector credential using the exact `PLATFORM_COLLECTOR_DIGEST` from step 2, **no domain and no public port**. Remove any generated proxy domain. If GHCR is private, give Coolify package read access. Confirm its container stays running before creating a task.

Do not configure an HTTP health path for a worker: it has no HTTP server. Check its running container state and scheduled-task execution history instead.

For each worker:

1. Read the real source identity. Create a scoped credential with `POST /metric-collectors`. Supply `scope`, `school_id` where applicable, `source`, `resource_ref`, and a reason. The response contains a one-time `token`; save it only as this worker's secret `METRICS_COLLECTOR_TOKEN`.
2. Set `METRICS_PLATFORM_URL=https://<platform-api-host>/metric-reports`. Use runtime-only secrets. Confirm the worker can reach the API.
3. Add source-specific variables and the command below. In **Scheduled Tasks → Add**, enter the command without `docker exec` and use a timeout of at least 60 seconds. Select **Execute now**, inspect **Recent executions**, then compare the received platform reading with the source before leaving the task enabled.

Coolify evaluates cron schedules in the deployment server's timezone. Confirm that timezone before using the times below; the minute offsets stagger the initial load.

| Source | Credential scope and reference | Additional worker variables | Command and starting schedule |
| --- | --- | --- | --- |
| Demo PostgreSQL size | `school`, `demo`, exact `sb_demo` database | Dedicated read-only `METRICS_DATABASE_URL` and `METRICS_DATABASE_NAME=sb_demo` | `node scripts/collect-database-size.js`, `7 * * * *` |
| St Paul PostgreSQL size | `school`, `stpaul`, actual database name | Its own read-only URL and database name | Same command, `17 * * * *` |
| Demo MinIO bucket | `school`, `demo`, exact Demo bucket | `METRICS_MINIO_URL`, `METRICS_MINIO_TOKEN`, `METRICS_MINIO_BUCKET` | `node scripts/collect-minio-bucket.js`, `27 * * * *`, after endpoint verification |
| St Paul MinIO bucket | `school`, `stpaul`, exact St Paul bucket | Its own bucket and metrics access | Same command, `37 * * * *`, after endpoint verification |
| Shared host/volume disk | `shared`, `host`, verified filesystem identity | `METRICS_DISK_PATH` = verified mounted path | `node scripts/collect-disk-headroom.js`, once per minute after safe mount verification |

For database jobs, provision a role that can connect to the intended school database and read `pg_database_size`, with no school table grants. Verify `current_database()` equals `METRICS_DATABASE_NAME`; the collector refuses a mismatch. For MinIO, verify the live `/minio/metrics/v3/cluster/usage/buckets` endpoint, scrape token, exact bucket label, and scan freshness. Do not assume the synthetic v3 test proves the deployed endpoint.

The disk collector measures the filesystem containing `METRICS_DISK_PATH` **inside its container**. Without an explicit verified mount it measures the collector container filesystem, not PostgreSQL or MinIO storage. Do not mount raw school database or MinIO data directories into a worker merely to obtain disk totals. Use a verified read-only host/volume mount or a host metrics agent; defer this source if a safe path cannot be established.

Container CPU/memory/restarts and per-school proxy error/latency collectors have no live integrations yet. Leave them unknown. The [source inventory](https://github.com/schoolbaseafrica/SchoolBase-Platform-BE/blob/main/docs/P1_6_SOURCE_INVENTORY.md) records the remaining work.

## 8. Review alerts, backups, and rollout

1. Keep `ALERTS_ENABLED=false` while source mapping or readings remain unverified. After continuous valid samples and threshold review, enable it on **one** API instance. Capacity and collection-stale alerts then appear in the dashboard. Acknowledgement records actor and reason; it does not resolve an incident or disable a school.
2. Compare Demo and St Paul readings with direct PostgreSQL/MinIO measurements, and shared disk with the actual host/volume. Record the sample time, source ID, resource reference, and any mismatch. A successful scheduled-task exit alone is not proof of attribution.
3. After each deployment, recheck database backup execution, API readiness, website login, school status, and collector task history. Record the Platform-BE and website commit IDs, plus the exact API and collector image tags.
4. If a rollout fails, disable the affected collector schedule or turn `PROBES_ENABLED`/`ALERTS_ENABLED` back off. Review migrations and backup state before rolling back the API image: a container rollback does not undo a forward-only database migration.

The pilot remains incomplete until live attribution, container/proxy metrics, availability alerts, alert email, and threshold calibration are finished.
