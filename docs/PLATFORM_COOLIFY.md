# SchoolBase platform: Coolify deployment guide

This guide deploys the private operator dashboard at `schoolbase.africa/admin` and prepares a Demo and St Paul pilot. The platform API and database are separate from each school's combined image and from the existing website backend. Keep the existing school and website databases unchanged.

The current code supports registry, availability probes, staff login and school database-size reports, capacity samples, trends, and dashboard capacity alerts. Container and proxy metric collectors, availability alerts, and alert email are still outstanding. The pilot is complete only after live readings are checked against their sources.

## 0. Record the inputs

Place the platform database and API on the same reachable Coolify destination network. Keep the website frontend in its existing resource; it may be in another project if its container can reach the API HTTPS route. Until organization package access is resolved, start the Platform build from `schoolbase-deployment`. This publishes distinct API and collector tags in the existing public `ghcr.io/donkross360/schoolbase` package, which Coolify already pulls for combined school images. The private Platform mirror offers a second build route, but its separate GHCR packages are currently private and cannot be pulled anonymously. Record the deployed backend commit and exact images from the workflow summary:

| Resource | Source | Build file | Internal port |
| --- | --- | --- | --- |
| Platform API | `schoolbase-deployment` `/compose.platform.yml` → published `schoolbase-platform-api` image | Backend `/Dockerfile` | 3010 |
| Existing website frontend | `schoolbaseafrica/SchoolBase-Website-FE`, `dev` | `/Dockerfile` | 3000 |
| Each private metric worker | Same deployment workflow → immutable `schoolbase-platform-collector` GHCR image | Backend `/Dockerfile.collector` | none |

Choose an HTTPS API hostname such as `api.platform.schoolbase.africa`. It must be reachable from the website server, school backends, and collectors. Protect the API route with a network, VPN, or IP restriction that admits those callers and the operator setup client. Do not enable Coolify HTTP Basic Authentication on this route: it uses the same `Authorization` header as the API bearer tokens. A gateway requiring extra service-token headers needs client support before use. If the route cannot be protected and reached by all callers, stop before adding school or collector credentials.

## 1. Create platform PostgreSQL

1. In the chosen Coolify project/environment select **New Resource → PostgreSQL**. Create a dedicated platform database and role, for example `schoolbase_platform`. Do not reuse a school or website database.
2. Select the same server and destination network as the API. Keep **public database access off**. Start the database and wait for the healthy state.
3. In its **General** page, copy the **Internal URL** and confirm its database name. Save that URL as the API's secret `DATABASE_URL`. Do not put it in Git, build arguments, or screenshots.
4. In **Backups**, add a recurring schedule and retention, run **Back up now**, and confirm a successful execution. Keep the database volume persistent.

Coolify's [PostgreSQL guide](https://coolify.io/docs/databases/postgresql) describes the private URL. Its [backup guide](https://coolify.io/docs/databases/backups) describes execution history.

## 2. Deploy the platform API

The organization Platform repo and its personal mirror are private. The mirror's own `GITHUB_TOKEN` can read its source and publish images under `ghcr.io/donkross360`. A build started in the public deployment repo needs an Actions secret named `PLATFORM_MIRROR_READ_TOKEN` to read the private mirror. Create a fine-grained personal access token under `Donkross360`, restricted to only `Donkross360/SchoolBase-Platform-BE` with **Contents: Read-only**; store it only in `Donkross360/schoolbase-deployment` Actions secrets. The build logic and smoke-test script remain in the deployment repo. Sync the exact approved Platform commit to the mirror before every build; the mirror is a build source, not an independent development branch.

1. In `Donkross360/schoolbase-deployment` on `main`, run **Actions → Build SchoolBase platform images → Run workflow** with `platform_ref=main` or a full 40-character mirror commit SHA. Wait for both image builds and smoke checks to pass. Confirm `Platform backend` SHA matches the approved organization commit, then copy `PLATFORM_API_DIGEST` and `PLATFORM_COLLECTOR_DIGEST` from the run summary. The summary also gives human-readable commit tags. Use the digest references in Coolify so a repeated build cannot silently change the deployed bytes.
2. In Coolify, select **New Resource → Public Repository** for `https://github.com/Donkross360/schoolbase-deployment.git`, branch `main`, **Docker Compose** build pack, base directory `/`, and Compose location `/compose.platform.yml`. This is a separate platform API resource; do not add it to either school's Compose resource.
3. Confirm the workflow summary uses `ghcr.io/donkross360/schoolbase` for both Platform images, with different `platform-api-` and `platform-collector-` tags. Test anonymous pull of both digest references before changing Coolify. This reuses the already public combined-image package and does not require a registry credential in application environment variables.
4. Set `PLATFORM_API_IMAGE` to the exact `PLATFORM_API_DIGEST` value from step 1. On the `api` service, configure the chosen HTTPS domain routed to internal port `3010`. Enable **Connect To Predefined Network** so the API can reach the private platform PostgreSQL resource on that destination. Leave Raw Compose Deployment disabled. Do not publish a host port.
5. Add the following Compose **environment variables** in Coolify. Mark `DATABASE_URL` secret; the Compose file passes them into the container:

   ```dotenv
   PLATFORM_API_IMAGE=ghcr.io/donkross360/schoolbase@sha256:<API digest from the successful run>
   DATABASE_URL=<platform PostgreSQL Internal URL>
   PROBES_ENABLED=false
   ALERTS_ENABLED=false
   ```

6. Deploy manually. The image applies numbered database migrations before starting. Check the GitHub Actions run for the build/source SHA, then Coolify **Deployment Logs** for the image pull and **Runtime Logs** for migration or startup errors.
7. From a client admitted by the API route, request `GET https://<platform-api-host>/health/live` and `GET https://<platform-api-host>/health/ready`. Both should return HTTP 200 with `{"status":"ok"}`. If readiness fails, fix the database connection or migration before continuing.

The API image already migrates on startup under a PostgreSQL advisory lock. Do not configure a second pre-deployment migration command. The workflow publishes images; Coolify uses the deployment repository's Compose file to pull them and apply runtime settings.

## 3. Create the first platform operator

1. Temporarily add `PLATFORM_BOOTSTRAP_EMAIL`, `PLATFORM_BOOTSTRAP_NAME`, and `PLATFORM_BOOTSTRAP_PASSWORD` as **runtime secrets** on the API resource. Use an individual operator email and a password of at least 12 characters. Redeploy so the container receives them.
2. In the API application's **Scheduled Tasks**, add a temporary task targeting the `api` container, with command `node scripts/bootstrap-admin.js`, timeout at least 60 seconds, and a non-imminent schedule such as `0 0 1 1 *`. Save it, select **Execute now** once, and inspect **Recent executions**. Expect `Initial platform administrator created`. Do not put the password in the command. This bootstrap refuses to run once any operator exists.
3. Delete the temporary task, remove all three bootstrap variables from Coolify, and redeploy. Recheck `/health/ready`. Keep the audit event and operator record in PostgreSQL.
4. From an admitted client, use `POST /operators/login` with that operator's email and password. The response has an eight-hour bearer token. `GET /operators/me` with that token should show `platform_admin`. Keep the token out of logs and documents.

If the first login is rejected after bootstrap, the API image includes `node scripts/recover-initial-admin.js`. Use it only while the database has exactly one active platform administrator and no other operators. Set temporary runtime-only `PLATFORM_RECOVERY_EMAIL` to that operator's email and `PLATFORM_RECOVERY_PASSWORD` to a **new** password of at least 12 characters. Mark the password **Is Literal** if it contains `$`, redeploy, and execute the script once through a temporary Scheduled Task targeting `api`. It changes the password, revokes existing sessions, and records an `operator.password_recovered` audit event. Confirm `Initial platform administrator password recovered`, delete the task, remove both recovery variables, redeploy, and sign in with the new password. Never put a password in the task command or logs.

Once the website frontend containing the school registration form is deployed (section 5), a platform operator can register each existing school at `/admin/schools/new`. Check the school list first to avoid duplicate records, enter the school's actual website and API origins, and give a reason. The form records the school and opens its detail page. The API procedure below is an alternative for setup clients with an operator token.

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
4. Confirm each school application uses `schoolbase-deployment` `main` and `/compose.school.yml` with the Platform activity environment mappings. Put Demo's token only in the Demo combined application's runtime `PLATFORM_SCHOOL_TOKEN`, and St Paul's token only in St Paul's. Check that `APP_SLUG` is `demo` for Demo and `stpaul` for St Paul, and that `DB_NAME` is the matching school's database (`sb_demo` or `sb_stpaul`). Set each application's `PLATFORM_ACTIVITY_URL=https://<platform-api-host>/school-signals/staff-login`. Redeploy each school application separately; adding a Coolify variable alone does not pass it into a Compose container unless the file maps it. New school images send `APP_SLUG` with each report; the Platform rejects a report if it differs from the school bound to the token. Older images omit this field and must still have their token checked manually. If a school reports under the wrong school, stop its reporting by clearing its token, correct the token assignment, and redeploy both schools so fresh reports replace the misattributed readings.
5. Within five minutes, inspect each school's platform status. `last_staff_login_at` reflects successful admin/teacher logins; no recorded login is different from an outage. Check each school's runtime logs for repeated report failures.

### Show the image reported by each running school

The combined school's Compose file passes its configured `SCHOOLBASE_IMAGE` into the app as `SCHOOLBASE_IMAGE_REF`. The existing school-scoped Platform report includes that reference on startup and about every five minutes, using the same `PLATFORM_SCHOOL_TOKEN` already configured for staff activity. Platform stores the latest report per school and records each image change. No Coolify API token, resource UUID, or manual release entry is needed.

1. Deploy the Platform API image with migration `007_school_runtime_image.sql` first. Redeploy the website frontend with the new dashboard next. Then build and deploy a new combined image for each school using `schoolbase-deployment/main` and the updated `/compose.school.yml`. The old school image cannot report its image reference.
2. Within five minutes, reload `/admin`. The overview shows each school's reported image. Open each school for its last received time and separate frontend/backend availability. **Refresh status** rereads Platform's most recent report; the school sends a new one on startup and every five minutes.
3. Compare Demo and St Paul's displayed image references with the `SCHOOLBASE_IMAGE` value on their respective Coolify resources. They must be distinct when the schools run different images. If a report is older than 15 minutes, Platform marks the image unavailable until a new report arrives.

### Show each school's database size

The school backend already receives `DB_HOST`, `DB_USER`, `DB_PASS`, and `DB_NAME`. It reads only `pg_database_size(current_database())` through that connection, verifies the returned name against `DB_NAME`, and includes the byte count in its existing school-scoped Platform report at most once per hour. No new Coolify variable, database role, collector token, worker, or Scheduled Task is needed for this reading. A failed size query does not stop staff activity or image reporting.

1. Deploy the Platform API image containing migration `008_school_database_size.sql` before deploying the new combined school image. The website frontend can be redeployed before or after the school image; it shows **Unavailable** until the first size report arrives.
2. Redeploy Demo's combined image, then open Demo's Platform detail page after its first report. Check **School-reported database size**, database name, source, and observation time. Do the same for St Paul. Each value is bound to the existing school token and must appear only under that school.
3. Compare each displayed byte count with `SELECT pg_database_size(current_database());` run against that school's database by its administrator. Record the difference and sample times. Do not treat the report as independently verified until this comparison passes. A missing or older-than-two-hours reading is unavailable.

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
| Demo MinIO bucket | `school`, `demo`, exact Demo bucket | `METRICS_MINIO_URL`, `METRICS_MINIO_TOKEN`, `METRICS_MINIO_BUCKET` | `node scripts/collect-minio-bucket.js`, `27 * * * *`, after endpoint verification |
| St Paul MinIO bucket | `school`, `stpaul`, exact St Paul bucket | Its own bucket and metrics access | Same command, `37 * * * *`, after endpoint verification |
| Shared host/volume disk | `shared`, `host`, verified filesystem identity | `METRICS_DISK_PATH` = verified mounted path | `node scripts/collect-disk-headroom.js`, once per minute after safe mount verification |

The separate database-size collector remains available if a school later needs an independent source. It is not required for this pilot. For MinIO, verify the live `/minio/metrics/v3/cluster/usage/buckets` endpoint, scrape token, exact bucket label, and scan freshness. Do not assume the synthetic v3 test proves the deployed endpoint.

The disk collector measures the filesystem containing `METRICS_DISK_PATH` **inside its container**. Without an explicit verified mount it measures the collector container filesystem, not PostgreSQL or MinIO storage. Do not mount raw school database or MinIO data directories into a worker merely to obtain disk totals. Use a verified read-only host/volume mount or a host metrics agent; defer this source if a safe path cannot be established.

Container CPU/memory/restarts and per-school proxy error/latency collectors have no live integrations yet. Leave them unknown. The [source inventory](https://github.com/schoolbaseafrica/SchoolBase-Platform-BE/blob/main/docs/P1_6_SOURCE_INVENTORY.md) records the remaining work.

## 8. Review alerts, backups, and rollout

1. Keep `ALERTS_ENABLED=false` while source mapping or readings remain unverified. After continuous valid samples and threshold review, enable it on **one** API instance. Capacity and collection-stale alerts then appear in the dashboard. Acknowledgement records actor and reason; it does not resolve an incident or disable a school.
2. Compare Demo and St Paul readings with direct PostgreSQL/MinIO measurements, and shared disk with the actual host/volume. Record the sample time, source ID, resource reference, and any mismatch. A successful scheduled-task exit alone is not proof of attribution.
3. After each deployment, recheck database backup execution, API readiness, website login, school status, and collector task history. Record the Platform-BE and website commit IDs, plus the exact API and collector image tags.
4. If a rollout fails, disable the affected collector schedule or turn `PROBES_ENABLED`/`ALERTS_ENABLED` back off. Review migrations and backup state before rolling back the API image: a container rollback does not undo a forward-only database migration.

The pilot remains incomplete until live attribution, container/proxy metrics, availability alerts, alert email, and threshold calibration are finished.
