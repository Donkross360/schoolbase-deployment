# CBT and virtual classroom architecture

This document records the implementation direction for SchoolBase assessment and live teaching.

## Delivery order

1. CBT foundation: examination authoring, class assignment, attempts, offline answer recovery, submission and scoring.
2. CBT operations: question bank, sections, manual marking, monitoring, analytics and result publication.
3. Classroom collaboration: scheduled sessions, presence, chat and a collaborative whiteboard.
4. Live teaching: voice messages and live audio, followed by optional screen sharing and video.

CBT does not depend on the real-time classroom services. A media outage must never prevent students from taking an examination.

## Current implementation and next step

The CBT foundation and administrator operations are implemented: separate internal and external examination flows, class-assigned student access, public applicant access, autosaved attempts, scoring, manual marking, question-bank reuse, monitoring signals, analytics and result publication. Student endpoints accept only in-school examinations; public applicant endpoints accept only entrance examinations. Browser activity is shown on demand in a compact drawer with review and acknowledgement controls rather than extending the result page indefinitely.

The role-scoped internal examination operations increment is implemented:

1. Administrators assign teachers to an internal examination and to an explicit subset of that examination's classes.
2. Assigned teachers receive a class-scoped live monitor containing only eligible candidates and attempts from those classes.
3. The monitor shows named not-started, online, reconnecting, submitted and awaiting-marking candidates, with answered progress and remaining time.
4. Browser activity opens in a compact drawer and supports acknowledgement without exposing answers or answer keys.
5. Proctor assignment, removal, activity review and acknowledgement actions are recorded in the activity log.
6. Examination authoring, answer keys, grading, result publication, admission actions and school-wide reporting remain administrator-only.

The Yjs collaboration foundation and page workspace are implemented. Short-lived classroom tickets authorize the collaboration namespace; PostgreSQL stores sequenced updates and compacted snapshots; reconnecting clients merge offline changes; and connected users receive complete presence snapshots instead of seeing only later joins. Teachers can create, rename, reorder and delete board pages, students can navigate them, and named cursor awareness remains ephemeral. Drawing permission changes are enforced against the live classroom state and broadcast to connected clients.

The next implementation increment is the **Excalidraw element adapter**. Each scene element must have its own Yjs identity so simultaneous changes merge at element level; replacing the visible canvas while continuing to save one serialized path value would still be last-writer-wins. The adapter must import the legacy first-page drawing once, preserve page snapshots, and keep media assets outside the Yjs update stream. Live audio, voice notes, screen sharing and optional video remain later media-service increments.

## CBT reliability contract

- PostgreSQL is authoritative for examination rules, attempts, answers and results.
- The browser writes every answer to IndexedDB before sending it to the API.
- Each saved answer carries a monotonically increasing revision. The API rejects an older revision when a newer answer already exists.
- Students can resume an active attempt. The server controls the deadline and maximum attempt count.
- Objective answers are scored on submission. Essays remain unmarked until reviewed.
- Answer keys and explanations are excluded from every student examination response.
- Connection changes and answer saves are recorded as attempt events for support and audit purposes.
- In-school examinations must be assigned to at least one class before publication.

The migration extends the restored `cbt_*` tables instead of replacing them, preserving legacy attempts and answers.

## Result lifecycle

Submitted attempts enter one of two states: automatically marked or pending manual marking. Administrators review the complete attempt, award marks for subjective responses, leave an internal marker comment and inspect the connection and visibility event timeline. Every saved manual mark records the marker and time in attempt metadata and recalculates the total score.

A result with unresolved manual responses cannot be released. Saving a new mark withdraws any earlier release until the updated result is reviewed and published again. Students and public candidates see scores immediately only when the examination explicitly enables immediate results; otherwise they see the score after an administrator publishes that attempt result. Answer keys remain restricted to the management review screen.

## Examination authoring

Draft examinations can be divided into ordered sections with their own instructions. Questions retain the selected section when the attempt is created, allowing the student and public candidate interfaces to show the current section while keeping one continuous autosaved attempt.

Examinations follow one controlled lifecycle: **draft → review → scheduled or active → closed → published → archived**. Draft papers remain editable. Review locks authoring while an administrator checks the paper. A future-dated paper may be scheduled, while a paper intended for immediate use becomes active. Only active examinations accept candidates. Closing prevents new attempts, publishing releases the final examination reporting state, and archiving removes the paper from routine operational views. Review and scheduled papers may return to draft when corrections are required.

The question bank stores independent copies rather than links to questions in an examination. An administrator can save a draft question to the bank, search the bank by question text or topic, and copy a bank question into another draft and section. Editing either copy cannot silently change an existing paper. Answer keys and explanations are returned only by authenticated management endpoints.

A draft can also be generated from a blueprint containing one or more rules for topic, question type, difficulty, section and count. Generation first returns a capacity report and the exact proposed questions; it does not mutate the draft. The administrator can regenerate the preview or accept it. Acceptance copies those exact bank questions into the draft.

Duplicate prevention is enforced by the API throughout authoring. A blueprint cannot select the same bank record twice, questions with equivalent normalized wording cannot appear across different rules, and questions already present in the draft are excluded. Manual creation, editing, question-bank import and final blueprint acceptance repeat the wording check so browser state cannot bypass it.

The question bank itself also has a normalized-wording uniqueness constraint. During migration, the earliest active copy of legacy duplicate wording is retained and later copies are archived. The management list performs the same normalization defensively so duplicate rows are not presented while a deployment is rolling forward.

## Examination navigation and entrance tests

The portal groups assessment tools under a **CBT** drawer:

- Internal Exams contains class-assigned school examinations.
- External Exams contains public entrance and recruitment-style tests.
- Applicants contains the candidate profile, attempts, score and admission action.

External candidates select a published examination on the public `/cbt` page and provide their name and email before starting. The email reuses the candidate's existing profile for that intake. Passing an examination lets an administrator start student onboarding with one action. Public attempt access uses a separate expiring token and never exposes answer keys.

The Applicants page is part of the CBT workflow, rather than an optional reporting screen. It must provide:

- a searchable, filterable list with applicant, intake, latest examination, attempt state, best percentage and admission state;
- summary counts for total applicants, passed applicants, attempts in progress and admitted applicants;
- an applicant detail view containing contact details and complete attempt history;
- a clear distinction between automatically scored attempts and attempts awaiting manual grading;
- admission eligibility based on a completed passing attempt, with manual grading completed where required;
- an idempotent admission action that reports whether it created a student, linked an existing student or sent an onboarding invitation; and
- explicit loading, empty, failure and retry states so an API failure is never presented as an empty applicant list.

Applicant records and attempts remain available after admission for audit purposes. Admission does not delete or rewrite the original external examination result.

Proctoring is configured per examination. The current recorded mode captures connection and page-visibility events for review; it does not claim to record a camera or microphone. Human monitoring can be added to the teacher and administrator views without changing candidate identity or scoring.

The examination management screen is also the first monitoring workspace. It refreshes active attempts without a page reload and shows completion, marking and publication counts, answered-question progress, connection interruptions and page-exit events. These signals are review aids rather than automatic proof of misconduct. Candidate names work for both enrolled students and public applicants.

## Academic-period visibility

Operational pages default to the active academic session and active term. Results, payment records, fee components, dashboard counts, class rosters, attendance, timetables, CBT examinations and CBT applicants must not silently mix historical periods into the current view. A user must explicitly select a previous session or term to see it.

CBT examinations and applicants use exact period membership. A term view contains only examinations assigned to that term and applicants with an attempt in that term; examinations without a term appear only in the whole-session view. Applicant details and admission actions reject a candidate who has no attempt in the selected period. The calendar date when an application or attempt was created is displayed separately from its academic-session label.

Legacy examinations that predate explicit period ownership are assigned to the session and term containing their earliest attempt date. They must never be attached wholesale to the session that happened to be active when the migration ran. This keeps historical external examinations and their applicants out of the current-period default while preserving them under explicit historical selection.

Academic-period selection is page scoped. Changing the period on Results must not change Fees, Attendance, Timetable, CBT or Dashboard. A list and its direct detail screen may share a scope when they represent one workflow, such as CBT Applicants and Applicant Details. Admin, teacher, student and parent portals each expose the selector on period-sensitive pages; pages containing global records do not show a misleading selector.

Class-based pages select a session because class enrollment and teacher assignment belong to a session. Monthly attendance selects a session and an explicit month. Term-based results select a session and term. When a session changes, a class selected in the previous session must be discarded if it is not part of the new session.

Fees have an explicit scope:

- A term fee appears for its term.
- A session-wide fee applies throughout its session and also appears in each term view for that session.
- A whole-session summary includes session-wide fees and all term fees in that session.

The dashboard displays its selected session and term beside its summaries so the scope is visible. Its selection remains independent from every other page.

Headline population cards are school-wide: all active students, teachers and parents remain counted even while they are awaiting a class assignment for the selected session. Session-sensitive cards and charts, including classes, enrollment growth, fees and activity, continue to use the selected academic period. Enrollment growth counts active class enrollments only.

Expected fees are assignment based. Each active fee is multiplied by the distinct active students reached through its assigned classes or direct student assignments. A student reached through both paths is counted once for that fee. Paid and outstanding totals use the same selected session and term, and currency is displayed at its real scale rather than rounding small amounts to zero millions.

## Classroom boundaries

The classroom will use three independent channels:

- SchoolBase API: session authorization, lesson metadata, durable chat records, attachments and attendance summaries.
- Collaboration service: WebSocket presence and conflict-free whiteboard updates.
- Media service: WebRTC live audio, video and screen sharing.

The collaboration service will use Excalidraw scene data with Yjs updates. It will persist periodic snapshots to PostgreSQL and assets to MinIO. Presence and cursor state are ephemeral and must not be written on every movement.

LiveKit Cloud is the initial media provider. Self-hosted LiveKit requires a separate media host, trusted TLS, TURN and the required UDP port range; it must not be added to the existing shared application host without capacity and network testing.

## Classroom session foundation

The first collaboration increment replaces the legacy class-ID-only contract with a scheduled classroom session. Each session belongs to one timetable schedule, class, subject, assigned teacher, academic session and optional term. This prevents an old classroom link from silently exposing a different academic period.

The SchoolBase API owns classroom scheduling, authorization, join/leave presence, durable text chat and teacher-controlled student chat and drawing permissions. Active participation records retain join, last-seen and leave times so attendance duration can be derived without treating a page view as full attendance. Teachers may access only sessions for their assigned timetable schedule; students must have an active enrollment in the session's class; administrators retain operational access.

The original polling whiteboard UI was a legacy class-ID client rather than the collaboration service. It is retained as the drawing surface while its authorization, persistence and navigation move onto the classroom-session contract.

The portal now opens classrooms by classroom-session ID. Teachers start a live lesson from an academic timetable entry, students receive a join action only while that lesson is live, and ending a lesson closes active participation records. Join, heartbeat and leave timestamps provide the attendance foundation. Durable text chat and teacher-controlled drawing permissions use the session authorization contract.

Whiteboard saves first gained an optimistic version so a stale writer could not silently overwrite a newer board. The classroom now uses a Yjs collaboration channel instead of whole-snapshot polling. A short-lived classroom ticket authorizes the WebSocket connection; incremental updates are sequenced in PostgreSQL, periodically compacted into recoverable page snapshots and replayed after reconnect. Presence and cursor-awareness events remain ephemeral. Changes made during a brief connection loss are merged and sent after synchronization.

The current drawing surface stores its existing canvas state in the shared Yjs document, preserving the deployed teacher and student workflow while establishing the conflict-free transport. Page creation and navigation, participant presence and named cursors now use that same contract. The next classroom increment replaces the legacy canvas adapter with an Excalidraw element adapter. It must reuse the current Yjs document and page contract rather than creating another persistence path.

## Classroom product rules

- A classroom session belongs to a timetable entry, class, subject and teacher.
- Teachers control drawing, chat and microphone permissions.
- The whiteboard uses pages and retains recoverable snapshots.
- Text messages and voice notes are durable; live audio is not recorded by default.
- Attendance derives from join and leave events and includes participation duration.
- Network failures retain the school identity and lesson context while showing a reconnecting state.
- Recording requires an explicit school policy, consent flow and retention period before it can be enabled.

## Deployment impact

The CBT release and initial collaboration channel use the existing SchoolBase backend, PostgreSQL and frontend image. Socket.IO is served through the existing backend HTTPS origin and reverse proxy, so it introduces no new public port. The ticket and namespace boundary allow the collaboration process to be extracted later without changing classroom identity or permissions. The media phase will add a separately deployable service and receive its own Coolify runbook before production rollout.
