# Revision practice

Implemented 2026-10-18. Open a submitted attempt's review, expand **Start a rework**, write a specific improvement goal, and choose guided or timed rework. A new workspace starts from that exact submitted source and exercise version. The original remains read-only.

## Preserved context

The new session has its own snapshots, timer, preparation requests, tests, hints, submission, and review. It does not inherit passing executions or observed ratings. Its saved context records the source revision, goal, earlier hint count, original focus, saved self-review, latest reported test summary for that revision, and completed advisory model feedback if available. Later edits to the original review do not replace the captured baseline.

The goal is limited to 1,500 characters. Submitted source is copied through normal workspace validation, including all seven system-design files together. Reworks retain the same exercise version; they do not silently translate old code to a new exercise contract. A rework can itself be submitted and reworked again.

Only one unfinished direct rework per source submission is allowed. An existing one is resumed, even if another tab sends a new request. Request UUIDs are idempotent, including retrying a request after its rework has been submitted. New reworks share the existing ten-unfinished-session quota. Timed rework starts its own clock explicitly and retains the normal executable-environment readiness requirement. It is labeled revision practice with prior exposure.

## Saved comparison

**Compare saved changes** in the workspace brief first saves local edits, then compares immutable saved snapshots. It lists added, removed, and modified files; unchanged files are counted separately. Original and rework line numbers remain visible. System-design comparisons also include static before/after architecture previews. No candidate code runs during comparison.

Line alignment uses bounded longest-common-subsequence work: at most 250,000 matrix cells and 10,000 middle lines. Larger changes display a replacement section with explicit omissions. Long unchanged sections collapse to context. Displayed output is bounded independently; long lines are shortened with a visible marker. Full files remain available in their workspaces. This is a source comparison, not proof that a fix is correct.

After submission, save the rework's own review to compare its self-ratings with the captured original review, provided both use the same published rubric. Missing entries remain unobserved. A changed file or higher self-rating does not establish correctness, retention, or independent interview performance.

## Progress and model context

Reworks remain in session history, attempt totals, and unfinished review queues with an explicit **rework** label. Their self-ratings do not add observations to starter-attempt trends, close starter-attempt gaps, or inflate recurring-gap counts. Practice from an exercise starter remains available through Progress to test whether an improvement carries over.

Model packets label submitted reworks and their prior exposure. Parent execution results are not attached as child execution evidence. The local model remains optional; creating, comparing, submitting, and self-reviewing a rework all work while it is offline.

## Access and verification

GET/POST `/api/sessions/:id/rework` reads rework status or creates/resumes a rework. POST takes `client_request_id`, `expected_revision`, `mode`, and `goal`. The source must be an owned submission. GET `/api/sessions/:id/rework_comparison` requires an owned rework and also checks ownership of its source. Writes retain normal authentication/CSRF protection; original snapshots and captured context have no update API. Database indexes enforce request identity and one unfinished direct rework.

Nine Rails integration tests cover all tracks, exact-version copying, separate evidence/timers, idempotency, frozen feedback, saved comparisons, self-rating separation, design artifacts, quotas, invalid inputs, and account boundaries. Four frontend tests cover source locations, repeated lines, trailing newlines, large replacements, large near-identical inputs, and escaping source/feedback.

The browser check created a clearly labeled **UI verification example** rework of the existing synthetic design submission. It remains an unsubmitted draft; its saved reliability edit is only a product test. The original submission was unchanged. Creation, source copying, save-before-comparison, reload persistence, and a 390-pixel mobile layout were checked. No actual model was invoked and no personal performance rating was added.
