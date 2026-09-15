# SchoolBase Coolify deployment contract

## Deployment model

One Coolify server runs shared PostgreSQL and MinIO services. Each school runs in
its own combined application container. The combined container contains the
Next.js frontend on port `3000` and the NestJS backend on port `3008`.

Each school has its own PostgreSQL database and role, MinIO bucket and user,
application configuration, JWT secrets, and public domains.

| School | Frontend | API | Database | Bucket |
| --- | --- | --- | --- | --- |
| Demo | `https://demo.schoolbase.africa` | `https://api.demo.schoolbase.africa` | `sb_demo` | `demo` |
| St Paul | `https://stpaul.schoolbase.africa` | `https://api.stpaul.schoolbase.africa` | `sb_stpaul` | `stpaul` |

## Traffic rules

Public domains are browser and external-client entry points. Container-to-
container traffic stays on the private `schoolbase-shared` Docker network.

```text
Browser -> frontend domain -> app:3000
Browser or external client -> API domain -> app:3008
Next.js server and API proxy -> 127.0.0.1:3008
NestJS backend -> schoolbase-postgres:5432
NestJS backend -> schoolbase-minio:9000
```

PostgreSQL port `5432`, MinIO API port `9000`, and MinIO console port `9001`
must not be published on the host. Coolify's proxy is the only public ingress.

## Runtime application variables

The application image must be reusable between schools. School-specific values
are runtime variables and must not be baked into the image.

### Required per-school variables

| Variable | Purpose | Demo example |
| --- | --- | --- |
| `NODE_ENV` | Enables production behavior and migrations | `production` |
| `PORT` | NestJS internal port | `3008` |
| `API_BASE_URL` | Next.js server-to-backend address | `http://127.0.0.1:3008` |
| `API_PUBLIC_URL` | Browser/external backend address | `https://api.demo.schoolbase.africa` |
| `FRONTEND_URL` | Allowed frontend and link base | `https://demo.schoolbase.africa` |
| `SUPERADMIN_LOGIN_URL` | Super-admin link base | `https://demo.schoolbase.africa/super-admin/login` |
| `CORS_ORIGINS` | Comma-separated allowed browser origins | `https://demo.schoolbase.africa` |
| `DB_HOST` | Private PostgreSQL service name | `postgres` |
| `DB_PORT` | Private PostgreSQL port | `5432` |
| `DB_NAME` | Isolated database | `sb_demo` |
| `DB_USER` | Role restricted to the school database | provisioned secret |
| `DB_PASS` | Password for the school database role | provisioned secret |
| `DB_SSL` | Private-network PostgreSQL TLS setting | `false` |
| `MINIO_ENDPOINT` | Private MinIO service name | `minio` |
| `MINIO_PORT` | Private MinIO API port | `9000` |
| `MINIO_USE_SSL` | Private-network MinIO TLS setting | `false` |
| `MINIO_ACCESS_KEY` | User restricted to the school bucket | provisioned secret |
| `MINIO_SECRET_KEY` | Secret for the school MinIO user | provisioned secret |
| `MINIO_BUCKET_NAME` | Isolated bucket | `demo` |
| `MINIO_PUBLIC_URL` | Base URL saved for browser-visible uploads | deployment-specific HTTPS URL |
| `JWT_SECRET` | Per-school access-token secret | generated secret |
| `JWT_REFRESH_SECRET` | Per-school refresh-token secret | generated secret |
| `UPLOAD_KEY` | Per-school unauthenticated upload key | generated secret |
| `APP_NAME` | Application display name | `SchoolBase` |
| `APP_SLUG` | Stable school/application identifier | `demo` |
| `SCHOOL_NAME` | School display name | deployment-specific |

Email, Paystack, Google OAuth, branding, log level, token duration, and invite
expiry settings remain optional until their corresponding feature is enabled.

`SCHOOL_NAME` is also the tenant-facing API identity. For example, Demo's API
documentation is titled **SchoolBase Demo API**. The immutable image must not
contain an old product or another school's name in Swagger, authentication-app
labels, or tenant welcome emails.

## Public website layout contract

Website layout is school data, not an image or environment setting. Each
school selects its layout under **Settings > Public Website**:

- **One-page website** keeps the public content on one scrolling page.
- **Multi-page website** provides separate Home, About, Academics, Facilities,
  Gallery, News, and Contact pages.

The backend stores the selection in `schools.use_marketing_site` and the
multi-page content in `schools.marketing_site_config`. Switching layouts must
preserve both one-page and multi-page content so a school can switch back
without rebuilding the image or re-entering information. The public `/` route
reads the school record and redirects to `/landing` or `/site` accordingly.

Administrators edit the selected layout under **Settings > Public Website**.
The multi-page editor must support page visibility and every field in the
stored configuration: Home images and facility highlights, page banners,
academic programs, facility and gallery images, news posts, and the Contact
image. Saving multi-page content must not change the selected layout or modify
the separately stored one-page content.

This setting must never be baked into `SCHOOLBASE_IMAGE`: Demo and St Paul use
the same immutable image while keeping independent layouts and content in their
separate databases.

## Build-time variables

No school-specific URL, credential, school name, or branding value may be a
required build argument. Next.js `NEXT_PUBLIC_*` variables are compiled into
browser bundles and therefore cannot be the primary multi-school configuration
mechanism.

The frontend must send relative backend requests through its same-origin
`/api/proxy-auth/*` route. The Next.js server resolves those requests through
the runtime `API_BASE_URL=http://127.0.0.1:3008` value. The public API domain
remains available for integrations and direct external API clients.

## Storage URL contract

`MINIO_ENDPOINT` is only for private backend-to-MinIO communication. It must
never be used to construct a URL returned to a browser.

The backend must use `MINIO_PUBLIC_URL` when it returns a persistent URL for an
uploaded public image. Bucket access remains limited to the corresponding
school's credentials for write and delete operations. If private documents are
added later, they must use authenticated download endpoints or short-lived
presigned URLs rather than persistent public URLs.

## Startup and migrations

Production schema migrations currently run through TypeORM while NestJS
initializes. A migration failure prevents NestJS from listening, which is the
desired failure behavior. Only one replica per school may start migrations at a
time until migration locking or a dedicated migration job is added.

The database-setup API writes credentials into an application-local `.env` file
and uses schema synchronization. It is unsuitable for an immutable production
container and must be disabled after infrastructure provisioning.

## Health contract

The existing deployment checks `/health`, but the backend does not currently
define that route. The application needs:

- a liveness endpoint that confirms the backend process is responding;
- a readiness endpoint that verifies PostgreSQL connectivity;
- a combined-container health check that verifies both ports `3000` and `3008`.

MinIO availability should be monitored separately. A temporary MinIO outage
should not destroy or recreate a school application container.

## Required application corrections

Before the reusable image is production-ready:

1. Make the frontend same-origin proxy the default for relative browser API
   requests and remove its dependency on a build-time API URL.
2. Set backend CORS from `CORS_ORIGINS` instead of accepting every origin.
3. Add `MINIO_PUBLIC_URL` and stop returning the private MinIO hostname.
4. Add valid liveness and readiness endpoints.
5. Disable the database-setup endpoint in provisioned production deployments.
6. Remove request bodies, authorization data, cookies, and tokens from proxy
   logs.
