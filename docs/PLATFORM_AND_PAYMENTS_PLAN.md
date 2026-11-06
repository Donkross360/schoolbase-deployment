# SchoolBase platform and payments: end-to-end plan

Status: agreed implementation sequence; design reference, not a record of completed work.

## Agreed order

1. School registry and status
2. Plans and offerings
3. SchoolBase subscriptions
4. Parent fee checkout

The first three phases concern the relationship between SchoolBase and each school. Phase 4 concerns parents paying their school. These are distinct payment flows and ledgers. Discussion of a school's existing Paystack account does not change this order.

## Current starting point

SchoolBase currently deploys each school as a separate Coolify application using the same combined image, with separate school database credentials and object storage access. Coolify is the deployment control plane. The proposed platform dashboard is a separate business and operations application, not a replacement for Coolify or for a school's admin portal.

The school application already has fee assignments, discounts, manual payment records, and a parent fee page. Its payment record is built around an already recorded fee payment. Online checkout therefore needs a separate pending-attempt record and a verified path into that ledger. The deployment configuration has a school-specific `PAYSTACK_KEY`, but that alone does not provide owner setup, checkout, webhook handling, or reconciliation.

## Phase 1 — School registry and status

Create a platform service and private dashboard for SchoolBase staff. Register each school with a stable platform ID, slug, display name, domains, Coolify resource reference, deployment image version, onboarding state, and support contacts. Do not put school application credentials or student data in the registry.

Show separate status signals:

- **Availability:** last successful frontend and backend health checks, check time, and recent failures.
- **Usage:** last successful staff login or other agreed activity signal, supplied by the school application. A healthy site is not necessarily an active school.
- **Deployment:** current immutable image tag and last deployment result, read from the deployment source or reported during rollout.
- **Capacity:** per-school application CPU and memory use against its configured limits, restart/OOM events, request errors and latency, and storage growth. Show trends as well as the latest sample so a brief spike is not mistaken for sustained pressure.

Storage needs two views: each school's database size and MinIO bucket/object usage, plus free space on the shared host and volumes. The school application currently has CPU and memory limits (defaults: one CPU and 1 GiB), while PostgreSQL and MinIO are shared. A full shared disk can affect every school, so host/volume alerts are separate from per-school usage alerts. Where a metric cannot be attributed reliably to one school, label it shared rather than inventing a school total.

Collect infrastructure metrics from a read-only metrics source or agent, not by exposing Docker/Coolify administrative credentials to the school application. A school may report its own database size through its existing database connection and authenticated status exchange; label that reading school-reported and compare it with a direct database measurement in the pilot. Collect school activity through the same authenticated exchange. Store timestamped samples with a retention policy and display the last successful collection time. Alert SchoolBase operators on sustained high memory/CPU, repeated restarts or OOM kills, rising errors, low disk headroom, and failed metric collection. Start with warning and critical thresholds; tune them from observed usage. Avoid automatic suspension or destructive cleanup based on a single alert.

Use a narrow, authenticated status exchange between each school and the platform. It must identify the school reliably and avoid exposing school data through a public health endpoint. Provide a platform audit trail for registry changes and status overrides. Coolify remains the tool that actually deploys or restarts applications.

**Complete when:** operators can identify every onboarded school, distinguish unavailable from inactive, see per-school and shared capacity trends, receive actionable alerts, and trace each displayed status to its source and timestamp.

## Phase 2 — Plans and offerings

Define a versioned plan catalog and explicit per-school entitlements. Separate the base plan from approved exceptions so an individual offering can be enabled or disabled for one school without silently changing the plan for everyone else. Record the actor, reason, effective date, and previous value for each change.

The platform owns the entitlement record; school applications consume a signed or otherwise authenticated snapshot and retain a short-lived local cache. Define what happens if the platform is temporarily unreachable before switching on enforcement. The backend enforces access to a paid feature; the UI reflects the same access and explains unavailable features. Disabling an offering must not delete existing school records.

Candidate offerings include face attendance, NFC attendance, live classrooms, meetings, and parent online fee payment. Plans may also define measured allowances such as storage, but usage measurement and warning thresholds must be proven before any limit is enforced. Final plan names, prices, limits, and trial terms are product decisions, not hard-coded deployment values.

**Complete when:** an authorized platform operator can change one school's offering, the school backend enforces it, the UI matches it, and the change appears in the audit trail.

## Phase 3 — SchoolBase subscriptions

Create a platform billing ledger for SchoolBase invoices and school payments. The school owner sees the current plan, billing period, invoice history, amount due, due date, payment status, and a Pay SchoolBase action in the school admin portal. The platform dashboard shows the same invoice and renewal state across schools.

Support monthly, termly, and yearly contracts. Termly dates should come from an explicit contract schedule rather than assuming equal-length terms. Define proration, grace periods, trials, taxes, failed payments, refunds, and manual adjustments before launch. Keep invoice issuance, payment attempts, verified receipts, and entitlement decisions as separate records. Never infer payment from a browser redirect alone.

Use **SchoolBase's own payment account** for this flow. Verify gateway events, match amount/currency/reference, and make fulfillment idempotent. On expiry, use an agreed grace and recovery policy; do not unexpectedly block access to school records or parent information. Record notification and enforcement events so support can explain what happened.

**Complete when:** a school can receive and pay an invoice; the platform and school portal agree on its status; duplicate or delayed gateway events cannot duplicate payment; and expiry behavior is demonstrated in a test school.

## Phase 4 — Parent fee checkout

Offer the school owner a payment-connection page. A school that already has a Paystack business can use its own account. The owner enters the necessary test/live credentials in a protected form, copies a school-specific SchoolBase webhook URL into Paystack, tests the connection and an end-to-end transaction, then enables parent online payments. Secret keys are stored encrypted, never returned to the browser, and never written to logs. Key rotation and disconnection are supported. A SchoolBase-managed split arrangement may be offered later as a separate settlement option; it is not required for a school using its own account.

On the parent fee page, show the selected student's bill, applied discounts, payments, adjusted balance, any transaction charge, and the amount to pay. The parent can pay only for a student linked to their account. The backend calculates the payable amount and creates a pending attempt with a unique reference before initiating Paystack checkout using that school's account. Decide whether partial payments are allowed, their minimum, allocation order across fee components, and who bears gateway charges before implementation.

Handle signed Paystack webhooks and a return-page verification request through one idempotent confirmation path. Validate the gateway reference, school, currency, amount, and successful status before creating fee payment records and allocations in a transaction. Enforce uniqueness on the gateway reference and attempt-to-payment link. A retry, duplicate webhook, or refreshed return page must not credit the bill twice. Pending and failed attempts do not reduce the balance. Refunds, reversals, and chargebacks need explicit ledger corrections and review, not deletion of the original payment.

Give parents a receipt and current balance. Give school admins a searchable view of attempts, successful payments, exceptions, gateway references, allocations, and a safe Recheck with Paystack action. Manual cash and bank transfer records remain available and clearly distinguished from verified online payments. Parents can still view fees when online checkout is unavailable; the pay action is gated, not the fee information.

**Complete when:** a test school and then one real school can reconcile parent payments against Paystack and the SchoolBase fee ledger, including discounts, partial payments, interrupted checkout, duplicate callbacks, and refunds.

## Sequential task list

Work from top to bottom. A task is complete only when its stated check passes; the next phase starts after the preceding phase's completion check above passes. Keep implementation changes and evidence linked to these IDs.

### Phase 1 tasks — School registry, status, and monitoring

1. **P1.1 — Define the operating contract.** Decide who can access the platform, what “live” and “last active” mean, which infrastructure metrics are available, sampling and retention intervals, alert recipients, and initial warning/critical thresholds. Check: record the definitions and data sources without conflating health, usage, and capacity.
2. **P1.2 — Create the platform service and access controls.** Add a separate platform database, authenticated operator roles, and an audit log. Check: school admins cannot access platform endpoints; operator changes record actor and time.
3. **P1.3 — Register schools.** Model stable school IDs, slugs, domains, deployment references, image tags, lifecycle state, and support contacts; import existing schools. Check: Demo and St Paul appear once each, and registry changes leave school databases untouched.
4. **P1.4 — Collect availability and deployment state.** Poll school frontend/backend health and read deployment state through a narrowly scoped integration. Check: outages, stale checks, and deployment versions show distinct statuses and timestamps.
5. **P1.5 — Collect school activity.** Report an agreed staff-login or activity signal from each school through an authenticated channel. Check: a healthy but unused school is visibly different from a recently used school; no student records cross into the platform.
6. **P1.6 — Collect capacity metrics.** Capture per-school app CPU, memory, restarts/OOMs, errors/latency, database size, and MinIO bucket usage; separately capture shared host and volume headroom. Check: each chart identifies its source, scope, and last sample; unattributable shared usage is not assigned to a school.
7. **P1.7 — Build the operator dashboard and alerts.** Add school list/detail views, trends, warning/critical alerts, acknowledgement, and collection-failure alerts. Check: simulated app pressure and low shared disk produce the expected alert without disabling a school.
8. **P1.8 — Pilot and calibrate.** Run against Demo and one other school, compare displayed measurements with infrastructure readings, tune thresholds, and document response steps. Check: operators can explain and act on a real or simulated alert.

### Phase 2 tasks — Plans and offerings

9. **P2.1 — Define the catalog and policy.** Agree plan names, included features, any measured allowances, exceptions, trial terms, and outage behavior. Check: a versioned catalog and decision record exist before enforcement code.
10. **P2.2 — Store plan assignments and overrides.** Add per-school effective dates, actor, reason, and history. Check: changing one school does not change another or rewrite past entitlements.
11. **P2.3 — Deliver entitlements to school apps.** Implement authenticated snapshot delivery, caching, refresh, and stale-state behavior. Check: a brief platform outage has the documented result, and a changed entitlement reaches the correct school.
12. **P2.4 — Enforce and display access.** Guard backend feature routes and jobs, then align navigation and messages in the UI. Check: direct API calls cannot bypass a disabled offering, while existing records remain readable under the agreed policy.
13. **P2.5 — Exercise changes and rollback.** Test enable, disable, expiry, override, cache failure, and rollback on Demo. Check: operator audit history and school behavior agree.

### Phase 3 tasks — SchoolBase subscriptions

14. **P3.1 — Set commercial rules.** Approve monthly/termly/yearly prices, term schedules, trial, proration, taxes, grace, refund, and expiry behavior. Check: examples for first purchase, renewal, upgrade, late payment, and cancellation have unambiguous invoice outcomes.
15. **P3.2 — Build the billing ledger.** Model contracts, invoice lines, invoices, payment attempts, verified receipts, adjustments, and immutable history in the platform database. Check: balances can be reconstructed without relying on logs.
16. **P3.3 — Issue invoices and show them.** Generate due dates and invoices; show plan, status, history, and Pay SchoolBase action to the school owner, with matching platform views. Check: both sides show the same amount, due date, and status.
17. **P3.4 — Take payments to SchoolBase.** Use SchoolBase's gateway account, unique references, signed webhooks, server verification, and idempotent fulfillment. Check: duplicate/delayed events and refreshed redirects cannot settle an invoice twice.
18. **P3.5 — Handle lifecycle and exceptions.** Notify before renewal, apply the agreed grace/expiry policy, support manual adjustments and refunds with audit, and provide reconciliation tools. Check: a failed payment and an expired contract follow the documented path without unexpected loss of school data.
19. **P3.6 — Pilot subscription billing.** Test in gateway test mode, then reconcile one controlled real-school invoice with the gateway and platform ledger. Check: finance and school owner agree on the paid state before wider rollout.

### Phase 4 tasks — Parent fee checkout

20. **P4.1 — Set fee-payment rules.** Decide partial-payment minimum, allocation order, payer of transaction charges, refund handling, and visibility when checkout is off. Check: example bills with discounts and earlier payments have agreed payable amounts.
21. **P4.2 — Connect a school's Paystack account.** Build owner-only credential entry, encrypted storage, key rotation, generated webhook URL, connection test, and enable switch. Check: no secret reaches a browser response, source repository, or log; school A's key cannot be used for school B.
22. **P4.3 — Create pending checkout attempts.** Recalculate the linked student's bill on the backend, reserve a unique reference, and initialize Paystack under that school's account. Check: forged student IDs or browser amounts cannot create an unauthorized or underpriced checkout.
23. **P4.4 — Fulfill verified payments.** Validate webhook signature and independently verify reference, school, amount, currency, and status; write fee allocations/payment atomically with uniqueness constraints. Check: retries, duplicate webhooks, callback refreshes, and concurrent requests credit the bill exactly once.
24. **P4.5 — Expose parent and admin views.** Show checkout, pending/success/failure, receipt and current balance to parents; show searchable attempts, gateway references, allocations, and recheck action to school admins. Check: manual and online payments remain distinguishable and balances match the fee ledger.
25. **P4.6 — Reconcile exceptions.** Handle abandoned attempts, delayed webhooks, key rotation, refunds/reversals/chargebacks, and alerts for unresolved mismatches. Check: each exception has an auditable correction path without deleting the original financial record.
26. **P4.7 — Pilot and expand.** Run test-mode end-to-end cases, then a small real payment for one school, reconcile against that school's Paystack settlement and SchoolBase ledger, and enable subsequent schools individually. Check: parent checkout stays disabled for a school until its own setup and test pass.

## Boundaries and shared rules

- **Money flows:** schools pay SchoolBase for subscriptions; parents pay the school for fees. Do not mix these receipts, gateway credentials, settlement accounts, or ledgers.
- **Authority:** SchoolBase platform operators manage plans and subscriptions. School owners manage their school's payment connection. School admins manage fee records according to their permissions. Parents pay only linked student bills.
- **Audit:** retain who changed configuration or adjusted a record, when, why, and the gateway reference where relevant. Operational logs supplement the financial ledger; they do not replace it.
- **Isolation:** every platform request and gateway event must resolve to one school before reading credentials or changing records. School-specific secrets stay out of the shared image and frontend.
- **Reliability:** use unique references, transactional fulfillment, retryable background reconciliation, and alerts for unresolved attempts. Log identifiers and outcomes without logging keys or sensitive payloads.
- **Rollout:** add schema and read-only views first, deploy to Demo/test mode, exercise failure cases, enable a controlled real-school pilot, reconcile settlements, then expand school by school. Keep switches off until each phase passes its acceptance checks.

## Decisions to settle before coding the relevant phase

| Phase | Decision |
| --- | --- |
| 1 | Which activity counts as “last active”; metric source, sample frequency, retention, storage attribution, and alert recipients/thresholds. |
| 2 | Plan catalog, per-school exceptions, measured allowances, trial terms, and behavior during platform outages. |
| 3 | Prices, termly invoice schedule, grace period, tax treatment, proration, and expiry behavior. |
| 4 | Partial-payment minimum, fee allocation order, gateway-charge bearer, refund workflow, and whether a future split option is needed. |

## Paystack references

- [Accept payments and verify amount/status](https://paystack.com/docs/payments/accept-payments/)
- [Verify transactions](https://paystack.com/docs/payments/verify-payments/)
- [Webhook signature verification](https://paystack.com/docs/payments/webhooks/)
- [API key types and handling](https://paystack.com/docs/developer-tools/api-keys/)
- [Subscriptions](https://paystack.com/docs/payments/subscriptions/)
