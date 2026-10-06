# SchoolBase upload review

Reviewed against the frontend, backend, and Coolify Compose source on 2026-10-06.
The highest proof level is host-tested. There was no local PostgreSQL, MinIO, or
authenticated Coolify session for a live upload test.

| Flow | Limit and validation | Storage and access |
| --- | --- | --- |
| General profile pictures and school logos | 5 MB; JPEG, PNG, WebP; backend checks file signatures and image metadata | MinIO public image prefixes |
| Student phone photo capture | 5 MB; expiring single-use token; image normalized before upload | `schoolbase-users/`; public profile URL also serves as the face reference |
| Teacher face check-in | 5 MB image and attendance authorization | Sent for verification; no new MinIO object |
| Student and parent CSV imports | 5 MB and 1,000 rows; required fields and row errors | Parsed in memory; no MinIO object |
| Invite CSV | 5 MB and 1,000 rows; role and CSV checks | Parsed in memory; sends invitation emails |
| Payment receipts | 5 MB; JPEG, PNG, PDF; backend checks signatures | New objects under private `receipts/`; admin download at `GET /fee-payments/:id/receipt` |
| Assignment attachments | 10 MB; MIME allowlist | Private `assignments/`; access checked on backend download |
| Classroom whiteboard images | 5 MB; image signature and metadata checks | Public `classrooms/*/whiteboard/` for embedded images |
| Classroom voice notes | 8 MB and 120 seconds; audio transcoded before storage | Private `classrooms/*/voice-notes/`; access checked on backend stream |

The prior MinIO provisioning rule enabled anonymous reads of the entire school
bucket. The revised rule permits anonymous reads only of the listed image
prefixes. Apply the new infrastructure image and rerun bucket provisioning
**before** deploying the backend that writes private receipts. An empty bucket
needs no legacy receipt migration. For a populated bucket, receipts already
under `schoolbase-uploads/` remain publicly readable and require migration.

Remaining proof: the infrastructure CI checks anonymous HTTP access to public
and private test objects, but this workflow has not been run here. Live upload,
download, and browser checks in Coolify remain necessary. Assignment attachment
types are currently checked by client MIME, without content signature validation.
Profile images, including photos used as face references, remain browser-visible
by design of the current UI; a private reference would require separate storage
and image delivery changes.
