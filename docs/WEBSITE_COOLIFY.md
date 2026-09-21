# Public SchoolBase website on Coolify

The public marketing website is independent of the per-school application
stack. Deploy it as three resources in one Coolify project:

1. a PostgreSQL database;
2. `SchoolBase-Website-BE` as a Dockerfile application on port `3008`;
3. `SchoolBase-Website-FE` as a Dockerfile application on port `3000`.

Keeping the frontend and API separate lets either service deploy without taking
the other one down. PostgreSQL must stay private and must not have a public port.

For the initial deployment, both Coolify applications track the `dev` branch.
They still run with `NODE_ENV=production`; the Git branch does not control the
runtime mode.

Both source repositories are public. In Coolify, choose **Public Repository**;
no GitHub App, deploy key, or organization installation is required. Automatic
deployments can be added later with a repository webhook.

## 1. Choose the domains

Use one public hostname for the site and one for the API. For example:

```text
https://schoolbase.africa
https://api.schoolbase.africa
```

Create both DNS records pointing to the Coolify server. The exact names may be
changed, but use the same values consistently below.

## 2. Create PostgreSQL

In the same Coolify project and environment, create a PostgreSQL resource. Use
a generated password and create a database and role dedicated to this website,
for example `schoolbase_website`. Do not expose port `5432` publicly.

Record the private hostname, port, database, username, and password shown by
Coolify. Both the database and API resource must be connected to the same
Coolify network.

## 3. Deploy the API

Create a Git-based application with these settings:

```text
Source type: Public Repository
Repository: https://github.com/schoolbaseafrica/SchoolBase-Website-BE.git
Branch: dev
Build pack: Dockerfile
Dockerfile location: /Dockerfile
Port: 3008
Domain: https://api.schoolbase.africa:3008
Health path: /api/v1/health
```

Add these runtime variables. Replace example values and keep database and mail
credentials marked as secrets:

```dotenv
NODE_ENV=production
PORT=3008
APP_NAME=SchoolBase Website
API_PREFIX=api
API_VERSION=v1
FRONTEND_URL=https://schoolbase.africa
CORS_ORIGINS=https://schoolbase.africa,https://www.schoolbase.africa
DB_HOST=<Coolify private PostgreSQL hostname>
DB_PORT=5432
DB_NAME=schoolbase_website
DB_USER=<website database user>
DB_PASS=<generated database password>
DB_SSL=false
MAIL_MAILER=smtp
MAIL_HOST=<SMTP host>
MAIL_PORT=587
MAIL_USERNAME=<SMTP username>
MAIL_PASSWORD=<SMTP password>
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=<verified sender address>
MAIL_FROM_NAME=SchoolBase
LOG_LEVEL=info
```

Deploy the API first. Its production startup runs the isolated website
migrations for the `waitlist` and `contacts` tables. Verify:

```bash
curl -fsS https://api.schoolbase.africa/api/v1/health
```

The response is wrapped by the API response interceptor and includes a healthy
`status` value. Swagger is available at `https://api.schoolbase.africa/docs`.

## 4. Deploy the frontend

Create another Git-based application:

```text
Source type: Public Repository
Repository: https://github.com/schoolbaseafrica/SchoolBase-Website-FE.git
Branch: dev
Build pack: Dockerfile
Dockerfile location: /Dockerfile
Port: 3000
Domain: https://schoolbase.africa:3000
```

Set this runtime variable:

```dotenv
API_BASE_URL=https://api.schoolbase.africa/api/v1
```

`API_BASE_URL` is intentionally server-only. Contact and waitlist forms call the
same-origin `/api/proxy-auth/*` route, and Next.js forwards them to this value at
runtime. Do not add a build-time `NEXT_PUBLIC_API_BASE_URL` unless a browser-only
feature explicitly needs to bypass that proxy.

Deploy the frontend after the API health check succeeds.

## 5. Verify the release

Open the website in a private browser window and check all of the following:

- the home page and static assets load over HTTPS;
- the browser has no mixed-content or CORS errors;
- a new waitlist submission succeeds and appears in PostgreSQL;
- a contact submission succeeds and appears in PostgreSQL;
- notification email delivery succeeds with the configured SMTP account;
- refreshing the site does not change the hostname or expose the API's private
  database connection details.

If a form returns a proxy error, inspect frontend logs first for connectivity to
`API_BASE_URL`, then API logs for database or SMTP failures. A database failure
prevents API startup; an email failure is logged separately after the contact is
stored.
