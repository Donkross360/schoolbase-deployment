# Enable face attendance in the Coolify deployment

The Git-based `compose.infrastructure.yml` deploys shared PostgreSQL, MinIO,
and CompreFace in one Coolify resource. CompreFace has its own PostgreSQL
container and named volume; it does not use either school's database. Each
school app uses `compose.school.yml` and joins the same `schoolbase-shared`
network. The older root `docker-compose.yml` is for the retired host-managed
deployment and is not used by the Coolify runbook.

## 1. Enable CompreFace in the existing infrastructure resource

The Coolify server needs an x86 processor with AVX. Check with
`lscpu | grep -i avx` before deployment. [CompreFace requirements](https://github.com/exadel-inc/CompreFace/blob/master/docs/Installation-options.md)

Check free memory and CPU. The default API and admin Java heap limits in
`compose.infrastructure.yml` are 4 GB and 1 GB, plus the face-processing
service and CompreFace's separate PostgreSQL container. Adjust
`COMPREFACE_API_JAVA_OPTS` and `COMPREFACE_ADMIN_JAVA_OPTS` only after
checking capacity. [CompreFace release defaults](https://raw.githubusercontent.com/exadel-inc/CompreFace/master/.env)

Commit and push the infrastructure Compose change. In the existing shared
infrastructure resource, reload the Compose definition from the selected Git
branch. Keep all current PostgreSQL and MinIO variables unchanged. Add a new,
unique `COMPREFACE_DB_PASSWORD` in **Configuration → Environment Variables**;
the CompreFace database is independent of `POSTGRES_ADMIN_PASSWORD` and the
school database passwords. Add `COMPREFACE_DASHBOARD_AUTH_USERS` manually as
described below before deploying this Compose revision. The optional values in
`config/infrastructure.env.example` include a pinned CompreFace image version,
dashboard port, and Java heap settings. Save and redeploy the infrastructure
resource. No second Coolify resource or pasted upstream YAML is needed.

The infrastructure Compose file includes CompreFace's five services and a
persistent volume named `schoolbase-compreface-postgres-data`. It hard-codes
`SAVE_IMAGES_TO_DB=false`, so submitted verification images are not retained
in CompreFace's database. The dashboard binds only to host loopback port
`18000` by default. The frontend joins its private CompreFace network,
`schoolbase-shared`, and Coolify's proxy network. On `schoolbase-shared` its DNS alias is
`schoolbase-compreface`. Schoolbase reaches it at
`http://schoolbase-compreface` on container port 80. [CompreFace upstream
Compose](https://github.com/exadel-inc/CompreFace/blob/master/docker-compose.yml)

Wait until all five CompreFace components are running. The first startup can
take over 30 seconds; check their Coolify logs if one fails. [CompreFace startup
guidance](https://github.com/exadel-inc/CompreFace/blob/master/docs/Installation-options.md)

To open its dashboard privately, create an SSH tunnel from your computer:

```bash
ssh -L 18000:127.0.0.1:18000 <ssh-user>@<coolify-server-ip>
```

Keep that SSH session open and visit `http://localhost:18000/login` in your
browser. If you changed `COMPREFACE_DASHBOARD_PORT`, use that port in both
places.

### Dashboard access without SSH

The Compose frontend also supports an HTTPS domain protected by Traefik basic
authentication. Before deploying this Compose revision in Coolify, generate a
strong dashboard password on your computer and create a bcrypt users entry
with `htpasswd -nB admin` (it prompts for the password). Set the output, in the form
`admin:$2y$...`, as `COMPREFACE_DASHBOARD_AUTH_USERS` in the **shared
infrastructure** resource's Environment Variables. This variable is referenced
only in a Compose label, so use **Add** if Coolify did not create it on reload.
Store the plaintext password in your password manager, mark the Coolify value
as a secret, and enable **Is Literal?** so Coolify keeps the dollar signs in
the bcrypt hash.

Reload the Git Compose definition. Under **Configuration → General**, assign
your HTTPS hostname to **Domains for compreface-fe** on container port `80`.
Point its DNS record to the Coolify server. Save and redeploy. Open the hostname
in a private browser window: it must request the basic-auth credentials before
showing CompreFace. Do not assign a public domain to `compreface-api`,
`compreface-admin`, or `compreface-postgres-db`. The SchoolBase apps continue
using `http://schoolbase-compreface` on the private Docker network, so browser
authentication does not affect their API calls. [Coolify Compose domains](https://coolify.io/docs/applications/builds/docker-compose), [Coolify Compose middleware](https://coolify.io/docs/core/networking/proxy/traefik/custom-middlewares)

## 2. Create verification services and keys

In the CompreFace dashboard, create an application for SchoolBase. For **each
school**, create a service with type **VERIFICATION** and copy that service's
API key. Use separate keys for Demo and St Paul so either school's key can be
rotated independently. SchoolBase compares the submitted live photo directly
with the student's approved reference photo; CompreFace does not need a student
face collection for this flow. [CompreFace service types](https://github.com/exadel-inc/CompreFace/blob/master/docs/Face-services-and-plugins.md#face-verification), [CompreFace verification API](https://github.com/exadel-inc/CompreFace/blob/master/docs/Rest-API-description.md#face-verification-service)

## 3. Build and manually deploy the SchoolBase image in Coolify

Use the existing image release flow. In the deployment repository's GitHub
Actions, run **Build SchoolBase image** with the intended frontend and backend
refs. Wait for the smoke test and image publish to succeed. Copy the complete
`SCHOOLBASE_IMAGE=...` value from the workflow summary.

For each school, open its existing SchoolBase Compose Application in Coolify and
go to **Configuration → Environment Variables**. Update `SCHOOLBASE_IMAGE` to
the copied immutable image reference; do not use `latest`. After setting the
face variables in the next step, save and manually trigger the Coolify
deployment as you normally do. `compose.school.yml` uses `pull_policy: always`,
so this deploy pulls the image you selected. The GitHub image build and the
Coolify deployment are separate steps. [SchoolBase Coolify
runbook](COOLIFY.md#1-build-the-application-image), [Coolify environment
variables](https://coolify.io/docs/services/configuration/environment-variables)

## 4. Add the provider settings to each SchoolBase Coolify resource

Open a school's SchoolBase **Application** in Coolify and go to
**Configuration → Environment Variables**. Add:

```text
FACE_VERIFY_URL=http://schoolbase-compreface
FACE_VERIFY_API_KEY=<that-school-verification-service-key>
FACE_MATCH_THRESHOLD=0.8
```

These variables must be present in Coolify and mapped into the app container by
`compose.school.yml`.
The URL is the internal Coolify network alias and must be the base URL only;
SchoolBase appends `/api/v1/verification/verify`. Do not use
`http://compreface:8000` or a public URL: this deployment uses
`schoolbase-shared`, and the API is reached inside the Docker network on port
80. Do not put the API key in a browser variable or in the Android app.

Repeat this step on every school's SchoolBase resource, using that school's
verification key. `FACE_MATCH_THRESHOLD=0.8` is the current starting value;
test with the school's devices and lighting before changing it. Raising the
value makes matching stricter and can reject more genuine check-ins.

With `SCHOOLBASE_IMAGE` and the `FACE_*` variables set, save and manually deploy
that SchoolBase resource. Production database migrations run automatically at
NestJS startup; the face attendance migration adds the required student photo
approval and attendance audit fields.

## 5. Enable Face and enrol students

In that school's SchoolBase admin portal, open **Settings → Attendance**, enable
**Face**, and save. The admin settings report Face as configured when both the
URL and key are present. This confirms environment configuration, not provider
health; finish the real check-in test to confirm network access and the key.

Each student must take a new photo in their portal settings. The admin reviews
and approves it on the student's page. Replacing the photo clears its approval.
Then a teacher can check the student in from the Android app or web portal.

## Troubleshooting

- **Face is still “not configured”:** in that school's Coolify Application,
  confirm all three `FACE_*` entries are saved and redeploy. Make sure the
  running Compose definition includes their environment mappings.
- **Provider timeout or unavailable:** confirm the SchoolBase app and
  `compreface-fe` both join `schoolbase-shared`, that CompreFace is running, and
  that `schoolbase-compreface` resolves from the SchoolBase app's Coolify
  terminal.
- **CompreFace rejects the key:** confirm it belongs to that school's
  **VERIFICATION** service, not Recognition or Detection.
- **Student cannot be verified:** confirm the reference photo has been
  captured and approved, and test image quality and the threshold. Failed
  comparisons do not record attendance.

The Android random movement prompt is a basic on-device presence check, not
certified liveness detection; a replay or modified app could defeat it. Keep a
teacher present. The web camera flow also relies on teacher supervision. The
SchoolBase backend does not retain the live check-in image; CompreFace image
storage should remain disabled as described above. SchoolBase retains the
student's approved reference photo in MinIO and records the attendance result
and similarity score.
