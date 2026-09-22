# CBT and virtual classroom architecture

This document records the implementation direction for SchoolBase assessment and live teaching.

## Delivery order

1. CBT foundation: examination authoring, class assignment, attempts, offline answer recovery, submission and scoring.
2. CBT operations: question bank, sections, manual marking, monitoring, analytics and result publication.
3. Classroom collaboration: scheduled sessions, presence, chat and a collaborative whiteboard.
4. Live teaching: voice messages and live audio, followed by optional screen sharing and video.

CBT does not depend on the real-time classroom services. A media outage must never prevent students from taking an examination.

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

## Classroom boundaries

The classroom will use three independent channels:

- SchoolBase API: session authorization, lesson metadata, durable chat records, attachments and attendance summaries.
- Collaboration service: WebSocket presence and conflict-free whiteboard updates.
- Media service: WebRTC live audio, video and screen sharing.

The collaboration service will use Excalidraw scene data with Yjs updates. It will persist periodic snapshots to PostgreSQL and assets to MinIO. Presence and cursor state are ephemeral and must not be written on every movement.

LiveKit Cloud is the initial media provider. Self-hosted LiveKit requires a separate media host, trusted TLS, TURN and the required UDP port range; it must not be added to the existing shared application host without capacity and network testing.

## Classroom product rules

- A classroom session belongs to a timetable entry, class, subject and teacher.
- Teachers control drawing, chat and microphone permissions.
- The whiteboard uses pages and retains recoverable snapshots.
- Text messages and voice notes are durable; live audio is not recorded by default.
- Attendance derives from join and leave events and includes participation duration.
- Network failures retain the school identity and lesson context while showing a reconnecting state.
- Recording requires an explicit school policy, consent flow and retention period before it can be enabled.

## Deployment impact

The first CBT release uses the existing SchoolBase backend, PostgreSQL and frontend image. It introduces no new service or public port. The collaboration and media phases will add separately deployable services and receive their own Coolify runbook before production rollout.
