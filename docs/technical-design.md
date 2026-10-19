# Technical design and decision register

Status: target architecture with a locally implemented application/worker foundation; see [implementation and limitations](../apps/platform/README.md). This is not a validated production deployment plan. No subscriptions or infrastructure purchases are authorized by these documents.

## Boundaries

Use a Rails application backend and React/TypeScript workspace with PostgreSQL, object storage, background jobs, isolated code runtimes, and AI/voice adapters. Keep the initial control plane cohesive rather than splitting every concern into a service.

The browser communicates with the authenticated control plane. The control plane authorizes runtime creation and brokers short-lived session-scoped access. Runtime workers receive exercise assets, not control-plane secrets. AI providers receive only context needed for their role.

Treat user code, terminal output, repository text, and conversation as untrusted data. They cannot modify evaluation rules, retrieve hidden material, or authorize tool actions.

## Conceptual interfaces

Exact URL/API syntax is deferred. Required operations:

| Area | Operations |
| --- | --- |
| Catalog | List exercise versions, inspect brief and permitted modes |
| Sessions | Create, prepare, start, inspect, pause if allowed, submit, abandon |
| Artifacts | Read tree, save file revisions, checkpoint, restore, export |
| Runtime | Connect terminal, execute/cancel, inspect readiness and usage |
| Design | Save diagram/notes revisions, select element, snapshot |
| Conversation | Send text, connect voice, interrupt, correct transcript |
| Review | Inspect status/results, start revision, compare revisions |
| Progress | Inspect evidence/recommendations, select next practice |
| Privacy | Configure retention, delete session/account data |

All artifact/session/review access is owner-authorized. Start, submit, and retry operations are idempotent. Concurrent mutations use expected revision IDs and return explicit conflicts. Stream events have monotonically ordered per-session sequence numbers; reconnect retrieves missed events.

## Persistence and evidence

Store authoritative session status, deadline, exercise/rubric versions, event sequence, and checkpoint IDs in PostgreSQL. Store large immutable artifacts in object storage with checksums and authorization checks.

Every execution references the exact snapshot it ran. Every finding references stable code revision/line, diagram revision/element, transcript turn, or execution ID. A changed artifact cannot silently redirect an old finding to new content.

Store transcript corrections as revisions. Record provider/model/configuration and rubric versions for evaluation reproducibility without storing credentials or unnecessary sensitive request data.

Autosave and runtime filesystem edits require one versioned workspace synchronization protocol. The editor and terminal must not operate as disconnected copies. Detect terminal edits and reconcile through revision events before acknowledging the next checkpoint.

## Runtime and grading

Own execution orchestration and use Railway as the only hosting provider, per [ADR 002](decisions/002-railway-only-budget.md). The [Railway Sandboxes adapter](../services/railway_worker/README.md) is implemented with simulated-provider tests; actual hosted execution remains unverified. The existing Docker/gVisor worker remains optional. Validate adversarial isolation, Rails compatibility, filesystem/terminal integration, startup latency, cancellation, teardown, and cost. Do not execute untrusted workloads on the application host.

Prepare immutable exercise environments with pinned dependencies. The target policy denies runtime networking by default; integration exercises use controlled fixtures or explicit destination permissions. Railway's `ISOLATED` mode denies private-network access but permits outbound internet. The adapter therefore additionally requires non-root network/PID/mount namespaces and an isolation probe; live kernel support and isolation remain unverified. Apply and verify CPU, memory, process, storage, execution-time, and output limits. Terminate idle environments after checkpointing according to the session policy.

Final grading creates a fresh runtime from the immutable submission. Prefer out-of-process/black-box API checks for API contracts. Any in-process grading is untrusted execution; keep grade accounting outside candidate control, inspect tampering signals, and do not assume a candidate process reporting success proves correctness. Hidden tests are not promised to remain secret when executed in the same trust boundary as candidate code.

Runtime status, application failures, and grading infrastructure failures are distinct. Retries cannot alter which code revision is assessed. Preserve diagnostics while redacting credentials and limiting output volume.

## Conversation and review

Conversation uses bounded recent turns plus a structured summary and requested artifact excerpts. Record which artifacts the interviewer saw. Workspace edits should not trigger unrestricted full-repository AI calls.

Voice adapter supports streaming input/output, interruption, transcript events, and cancellation. Select transport and providers after latency experiments. Text remains functional independently of voice.

Review jobs are idempotent per submission/evaluation configuration. Produce schema-validated findings, verify references, check assertions against execution, deduplicate findings, and label uncertainty. If evaluation fails, retry analysis without rerunning or changing candidate work unnecessarily.

Do not give the interviewer unrestricted terminal tools. Explanatory test runs use bounded, authorized execution through the runtime service.

## Retention and costs

Proposed defaults: no retained raw audio unless enabled; keep session artifacts until deletion; show a retention policy before enabling recordings. Specify backup expiry during provider selection. Active processing may transiently handle audio even when recording storage is disabled.

Track runtime minutes, AI input/output usage, voice usage, storage, and egress per session. Cost model: fixed hosting + runtime hours × runtime rate + AI usage × model rates + audio usage × rates + storage/egress. Current dollar estimates require researched provider rates and workload measurements.

Use configurable spending/usage caps with warnings before a session starts if resources are insufficient. Never truncate a timed session silently because an internal review consumed the budget.

## Decision register

| Decision | Status | Resolution gate |
| --- | --- | --- |
| Hosted web app, voice/text, three deep tracks | User confirmed | Product baseline |
| Rails backend, React/TypeScript frontend | Rails implemented; initial browser uses a native JS module/plain-text editor | Advanced frontend integration remains open; domain/API boundaries are independent |
| Runtime platform | Own orchestration; Railway-only hosting | See [ADR 002](decisions/002-railway-only-budget.md); adapter implemented locally; hosted bootstrap, isolation checks, and cost validation remain |
| AI and voice providers/models | Open; no additional paid services | Establish a no-additional-cost option and verify quality/latency before integration |
| Editor/canvas libraries | Open | Accessibility, serialization, licenses, usability |
| Hosting region and providers | Railway only; region open | Existing project compatibility, privacy, available allowance, recovery |
| Framework/dependency versions | Open | Verify supported releases at implementation time |
| Usage budget | Existing Railway allowance; no extra spending authorized | Check available allowance and measure representative sessions before hosted execution |
| Assessment interruption policy | Proposed | Review against user expectations |

Open implementation decisions do not block completion of the product planning package. Record chosen providers and researched facts in later architecture decision records rather than treating this proposal as verified vendor guidance.
