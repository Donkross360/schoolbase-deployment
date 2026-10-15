# School Android app releases

The Admin Settings → Mobile App page reads `mobile-app/current.json` from the
school's private MinIO bucket. It shows no download until a signed release is
published. The authenticated backend streams the APK; the bucket remains
private. The existing **Build SchoolBase Android APK** workflow produces a
debug test artifact only and does not publish it to a school.

## Configure one GitHub environment per school

Create an environment named `school-<slug>` in the deployment repository. The
slug must match the school's MinIO bucket, such as `school-demo` with bucket
`demo`. Add these environment secrets:

| Secret | Value |
| --- | --- |
| `MINIO_BUCKET` | Exact school bucket name |
| `MINIO_ENDPOINT` | Public HTTPS MinIO API origin, for example `https://files.schoolbase.africa` |
| `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY` | Credentials provisioned for that school bucket |
| `ANDROID_KEYSTORE_BASE64` | Base64 encoded release keystore |
| `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | Release key credentials |
| `ANDROID_SIGNING_CERT_SHA256` | SHA-256 certificate digest shown by `apksigner verify --print-certs` |

Keep each school's release signing key stable. Android updates require the same
package ID and signing certificate as the installed version. Store the keystore
and its recovery copy outside this repository. Configure environment reviewers
if release publication should require approval.

## Publish a release

Run **Publish school Android app** manually. Provide the school slug, app name,
that school's HTTPS API URL ending in `/api/v1`, a reviewed full mobile commit SHA, a
semantic version, and a build number greater than the currently published one.
The workflow runs Flutter analysis and tests, builds a release APK using
`com.schoolbaseafrica.<slug>` as its package ID, checks its certificate and
package ID, computes its SHA-256 digest, and uploads it to
`mobile-app/releases/<sha256>.apk`. It checks the uploaded size, then writes
`mobile-app/current.json` last. A failed build or upload leaves the previous
release selected.

The API reads only the bucket configured for its school container. Admins can
view the version, size, publication date and checksum, then download through
an authenticated route. The release APK and manifest are outside the MinIO
public image prefixes; do not add them to the anonymous read policy. No shared
infrastructure redeploy is needed if the current per-school MinIO policy is
already in place.

Before giving a new school its first APK, install it on a test device and
verify login, school branding, and an API action against that school's Demo or
staging environment. No release has been published merely by adding this
workflow or the settings page.
