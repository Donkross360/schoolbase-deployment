# Coolify deployment runbook

## 1. Build the application image

The frontend and backend application corrections must first be committed to
their `feat/runtime-templating` branches.

In the deployment repository, run the **Build SchoolBase image** GitHub Actions
workflow. Select the exact frontend and backend refs. The workflow starts the
combined image with temporary PostgreSQL and MinIO services and verifies the
Demo frontend, backend readiness endpoint, and runtime school name. After the
smoke test passes, it publishes a GHCR tag containing both resolved commit SHAs.
Record the complete image name; do not replace it with `latest`.

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
host port mappings. MinIO joins Coolify's external `coolify` network for proxy
routing and the private `schoolbase-shared` network for application traffic.
The `traefik.docker.network=coolify` label makes the proxy select the reachable
interface when both networks are attached.

Deploy and wait for PostgreSQL and MinIO to become healthy. Confirm that Docker
network `schoolbase-shared` and volumes `schoolbase-postgres-data` and
`schoolbase-minio-data` exist.

## 4. Provision each school without server SSH

Add all variables from `config/infrastructure.env.example` to the infrastructure
resource in Coolify, then reload the Compose file and redeploy. Keep passwords
and secret keys marked as secrets. The infrastructure images contain the
provisioning scripts inside the PostgreSQL and MinIO containers.

In the infrastructure resource, open **Scheduled Tasks** and create these four
tasks. Select the listed service/container and use the exact command. The cron
schedule can be annual because provisioning is normally triggered with
**Execute Now** and is safe to rerun.

| Task | Service/container | Command |
| --- | --- | --- |
| Demo database | `postgres` | `/bin/sh /opt/schoolbase/provision-postgres.sh demo` |
| St Paul database | `postgres` | `/bin/sh /opt/schoolbase/provision-postgres.sh stpaul` |
| Demo bucket | `minio` | `/bin/sh /opt/schoolbase/provision-minio.sh demo` |
| St Paul bucket | `minio` | `/bin/sh /opt/schoolbase/provision-minio.sh stpaul` |

Run each task with **Execute Now**. A successful result ends with either
`PostgreSQL resources for <school> are ready.` or
`MinIO resources for <school> are ready.` No database or object-store password
appears in the task command or task log.

This provisions database `sb_demo`, database role `sb_demo_app`, bucket `demo`,
and Demo-only MinIO credentials. St Paul receives database `sb_stpaul`, role
`sb_stpaul_app`, bucket `stpaul`, and separate MinIO credentials.

The current upload feature returns persistent image URLs, so set
`MINIO_BUCKET_PUBLIC_READ=true`. This grants anonymous object downloads only;
database and MinIO write credentials remain school-specific. Do not use this
mechanism later for private documents.

Rerunning provisioning keeps existing data and credentials. If supplied
credentials do not match an existing role or user, verification fails instead
of changing the credential silently.

If a configured school credential was a placeholder or must be rotated, replace
the value on the infrastructure resource, redeploy, and execute the matching
tasks once with an explicit `rotate` argument:

```text
/bin/sh /opt/schoolbase/provision-postgres.sh demo rotate
/bin/sh /opt/schoolbase/provision-minio.sh demo rotate
```

Rotation changes only the selected role password and MinIO user secret. It
leaves the database contents, bucket objects, and access policy intact.

## 5. Restore the databases without server SSH

Set `RESTORE_MINIO_ACCESS_KEY` and `RESTORE_MINIO_SECRET_KEY` on the
infrastructure resource, reload Compose, and redeploy. The transfer bucket is
private and its credentials are separate from each application's credentials.
Confirm that `MINIO_PUBLIC_URL=https://files.schoolbase.africa` and its DNS A
record resolves to the Coolify server before generating an upload command.

For Demo, create a MinIO Scheduled Task using container `minio` and command:

```text
/bin/sh /opt/schoolbase/prepare-database-import.sh demo
```

Execute it and copy the one-hour `curl` upload command from its output. Run that
command locally from the directory containing `sb_demo.sql.gz`. After the upload
finishes, create a PostgreSQL task using container `postgres` and command:

```text
/bin/sh /opt/schoolbase/restore-postgres.sh demo
```

Execute the restore task. It validates gzip integrity, refuses a populated
database, changes object ownership from `postgres` to `sb_demo_app`, verifies at
least 59 tables, and deletes the transfer object after success. Use `stpaul` in
both commands for the St Paul backup.

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
`schoolbase-shared` network for PostgreSQL and MinIO access. It does not publish
either application port. Under **Configuration > Advanced**, enable **Connect
To Predefined Network** so Coolify adds its managed destination network and
generates the proxy labels. The Compose file pins Traefik to the external
`coolify` network so the proxy does not select the private database network when
the container has several network attachments. Keep Raw Compose Deployment
disabled.

Deploy Demo and run:

```bash
FRONTEND_URL=https://demo.schoolbase.africa \
API_PUBLIC_URL=https://api.demo.schoolbase.africa \
./scripts/verify-school.sh
```

Verify administrator email login and student login with a registration number,
restored records, a new image upload, and the resulting
`files.schoolbase.africa/demo/...` URL before continuing. In **Admin >
Results**, confirm submissions first appear by stream, then by class, and that
the Pending filter returns submitted results awaiting review.

In **Settings > Public Website**, confirm that the restored website layout is
selected. Demo's restored value is **One-page website**. Switching to
**Multi-page website** changes the public root to `/site` and uses the saved
multi-page content; switching back keeps that content available for later.
While Multi-page is selected, edit navigation labels and page text, upload or
replace an image, and edit one repeatable item. Save once and open **Preview
published site**. Confirm page visibility, wording, Home facility images,
programs, galleries, news, and Contact images match the saved values. Switch
back to One-page and confirm its images and testimonials remain unchanged.

## 7. Deploy St Paul

Create another Coolify application from the same Compose file and immutable
image. Use St Paul's environment values and configure:

```text
https://stpaul.schoolbase.africa:3000
https://api.stpaul.schoolbase.africa:3008
```

Deploy and run the verification script with the St Paul URLs. Confirm Demo
remains available during the St Paul deployment.

Choose St Paul's public website layout under **Settings > Public Website**.
This choice belongs only to St Paul and does not change Demo even though both
applications use the same image.

### Verify tenant identity during an outage

After each school has loaded successfully once, temporarily block or stop that
school's backend and refresh its frontend. The frontend stores the last valid
runtime school configuration under the exact browser hostname, so St Paul can
continue to show St Paul branding and Demo can continue to show Demo branding.
The cache does not cross hostnames even though both applications use the same
image.

Also test in a new private browser window with no cached configuration. If the
backend and the container runtime-config endpoint are both unavailable, the
page must show the neutral SchoolBase availability message. It must never show
the sample profile or another school's name. Restore the backend and use **Try
again** to confirm normal branding returns.

## 8. Coolify networking setting

The Compose definitions explicitly use the external `schoolbase-shared`
network. Application resources use Coolify's **Connect To Predefined Network**
setting for managed proxy routing; do not reproduce that destination network in
the school Compose file. Keep Raw Compose Deployment disabled. If Coolify
reports that the shared network is missing, deploy the infrastructure resource
first rather than creating another network with a different name.

School containers reach the shared services through the unique aliases
`schoolbase-postgres` and `schoolbase-minio`. These names avoid collisions with
generic service names on other Coolify networks attached to the same container.
