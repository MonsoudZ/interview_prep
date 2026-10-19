# Application foundation verification

Client date: 2026-10-16. Local development on macOS, Ruby 4.0.1, Rails 8.1.4, SQLite.

## Automated evidence

- `ruby bin/rails test`: **42 runs, 337 assertions, zero failures/errors, two skips**. This is 40 passing tests; live runtime checks remain opt-in. The Linux VM check was run separately on 2026-10-17 and passed with **1 run, 39 assertions, zero failures/errors/skips**. Railway execution remains unverified.
- `ruby bin/rails zeitwerk:check`: application eager-load check passes.
- `node --check public/app.js` and `node --check public/practice.js`: syntax passes.
- Python worker suite: **27 tests pass**, including three real local Rails entrypoint checks for readiness, 12 starter failures, and reference success (12 tests/158 assertions). Docker process tests use a fake executable/mocks; no isolation claim is made.
- Railway adapter: **27 Node tests pass**, covering signed contracts, provider lifecycle, policy gating, bounded output/time, cleanup, replay, callback recovery, quota/readiness, and checkpoint construction with fake VM transport. The installed official SDK is pinned to 3.16.0. These are not actual Railway VM tests.

Rails integration coverage: private resources, account lifecycle, normalization, password validation, CSRF, rate limits, all-track catalog, persistence, cross-account isolation, optimistic conflicts, invalid paths/maps, preparation gating, disconnected-worker gating, changed-source preparation, deadline submission, immutable/idempotent submission, queue idempotency/quota, service authentication, one lease per worker, invalid callback leases/revisions/status, callback idempotency, lease expiry, immutable content, and Ruby/Python signature compatibility.

Worker callbacks in API tests are explicitly synthetic fixtures. They verify queue/lease/results behavior, not live test execution or AI evaluation.

Practice/review integration coverage: support for all three exercise versions; progressive reveal without unrevealed bodies; recorded assistance; stale hint requests; assessment/submission hint restrictions; review gating; all-track rubrics; persisted source-bound evidence and reflections; optimistic review conflicts; invalid ratings/criteria/paths/ranges; explanation requirements; unobserved and reflection-only reviews; owner isolation; exclusion of preparation and other source revisions from execution evidence; and deadline-triggered submission review.

Railway presentation/contract coverage: Ruby-issued signatures verified by the real Node contract (including UTF-8 source); provider validation in callbacks; source-bound runner-reported starter/reference counts; exclusion of infrastructure, timeout, partial, and preparation output from complete-suite summaries; preserved execution revisions after further edits; and owner-scoped lease-expiry reconciliation during workspace polling when the worker disappears.

## Browser evidence

Verified the local app in the in-app browser:

1. Created a development-only `preview@example.test` account and saw dashboard/library.
2. Opened the Rails brief and created a guided session.
3. Edited the controller and saved a new revision.
4. Queued tests; UI correctly showed no connected worker and a queued request.
5. Started untimed practice.
6. Submitted through an in-page confirmation; save/edit controls became read-only.
7. Reopened the session URL and confirmed the saved controller text and submitted revision survived.
8. Inspected desktop layout at 1440×960 and the default narrower layout. This is visual inspection, not a complete accessibility audit.

Practice/review browser verification: created a separate guided Rails attempt under the existing local preview account; revealed two hints and inspected the analogous Bookmark API example; started/submitted; rated an unfinished HTTP contract; attached controller lines 3–5 and inspected the excerpt; saved a reflection; observed the gap-based practice recommendation; reloaded/reopened and confirmed the rating, source reference, reflection, and recommendation persisted. This was a labeled local verification example against placeholder code, not a claim about the user's performance.

Execution UI browser verification: reloaded the updated app, requested a run on the preview attempt, and observed the actual queued revision, waiting message, disconnected-worker state, and execution history. No completed Railway execution/counts were fabricated in the browser. Preview: [execution queue](../../artifacts/execution-queue.jpg).

2026-10-17 local VM update: the actual long-running local bridge consumed that queued starter job and the browser displayed 12 failures. A separate guided preview attempt saved the labeled trusted reference/model, prepared the VM, started, and ran successfully: **12/12 passing, 158 assertions**. Results and saved source survived refresh. See [passing browser results](../../artifacts/local-vm-tests-passing.jpg) and [VM verification](../../deploy/local-vm/VERIFICATION.md). The narrow layout's file sidebar was capped to the editor height to remove an empty gap above the brief.

An early browser-native confirmation caused automation trouble. It was replaced with an in-page dialog and the revised submission flow was verified. Asset cache settings were corrected to ensure updated code loaded.

## Unverified / incomplete

The local Linux/Docker/gVisor queue-to-result flow now passes, including observable isolation and an independent cleanup check; see [VM verification](../../deploy/local-vm/VERIFICATION.md). PostgreSQL concurrency, deployment/TLS, adversarial/resource-exhaustion testing, persistent terminal/editor synchronization, distributed worker identity rotation, production shared rate limiting, recovery email/verification, storage quotas, and operations under load remain unverified.

Ruby now has isolated execution (version 2), visible/supplemental tests, hints, and submission self-review. System design has saved notes, hints, and self-review. Its canvas, voice, conversational coaching, calibrated AI review, live Railway sandbox validation/deployment, and further curriculum expansion remain future milestones. No automated pass verdicts or fake execution output are presented.

## UI and workflow refresh · 2026-10-17

Reworked the dashboard, library, session setup, and editor using a shared green/neutral visual system. The overview emphasizes continuing saved work. Setup uses explicit guided/timed mode cards. The workspace prioritizes editable files, collapses fixed exercise files, formats brief paragraphs/lists/code, and separates Brief, Support, and Runs with keyboard-accessible tabs. Save and run shortcuts are available. Submitted sessions show a preserved snapshot and a direct review action. Failed test summaries have a distinct presentation.

Verified in the in-app browser at the default 1280×720 viewport and at 390×844: dashboard navigation, library/filter selection with retained keyboard focus, mode radio selection/cancellation, saved-session reopening, tab arrow navigation, selecting earlier run output, direct submission review opening/closing without changes, and responsive layout. Mobile document width equals viewport width (390px), and sign-out remains accessible. This is focused browser QA, not a complete accessibility audit. Existing preview reference source and review entries were preserved.

A fresh real run through the updated Run tests button transitioned from queued/disabled to finished/enabled with **12 tests, 158 assertions, zero failures/errors/skips** on the labeled reference attempt. These results are runner evidence, not a user performance assessment or AI grade. Ordinary Rails checks: **42 runs, 337 assertions, zero failures/errors, two expected opt-in skips**. Both JavaScript files pass Node syntax checks. No browser console errors were observed on the final preview tab.

During verification, found that Colima overwrote the guest-only gVisor Docker registration on restart. The dedicated interview profile now persists `docker.runtimes.runsc.path: /usr/local/bin/runsc`; the VM was restarted and the real browser run above passed afterward. No ordinary-runtime fallback was introduced. The local app and bridge are running together using the existing private launcher configuration.

Previews: [overview](../../artifacts/ui-refresh-overview.png), [workspace](../../artifacts/ui-refresh-workspace.png), [mobile](../../artifacts/ui-refresh-mobile.png), [review](../../artifacts/ui-refresh-review.png).

### Visual simplification · 2026-10-17

Removed motivational headlines, dashboard stat tiles, tinted hero banners, sidebar/footer slogans, decorative track icons, and repeated home-page attempts. Navigation is now Practice / Exercises / Sessions. Exercises use plain rows with direct Open actions, concise descriptions, duration, and actual workspace format. Ongoing attempts and recent submissions are separate sections. Updated setup/auth/workspace copy, reduced uppercase tracking, and increased reading sizes; session persistence and execution behavior are unchanged.

Browser checked: default narrow layout, 1280×800 desktop, and 390×844 mobile; filters, library navigation, exercise-mode dialog/cancellation, and saved workspace reopening. Mobile document width is 390px with no horizontal overflow. Viewport override was reset afterward. Existing source and results were preserved; displayed test results are from the previous verified runtime run, not a new execution in this visual pass. Node syntax checks pass. Rails suite: 42 runs / 337 assertions / zero failures or errors / two opt-in skips.

Previews: [simplified practice](../../artifacts/ui-refined-practice.png), [workspace](../../artifacts/ui-refined-workspace.png), [mobile](../../artifacts/ui-refined-mobile.png).

## Editor and interview workflow · 2026-10-17

Implemented all five requested improvements:

- CodeMirror 6 served from the app: syntax highlighting for Ruby/Markdown/JSON/YAML, line numbers, search/replace, indentation, file-local undo history, and read-only exercise/submission views. The build is pinned in package-lock.json, and the generated bundle includes third-party license notices. No runtime CDN or paid editor service.
- Pointer- and keyboard-adjustable explorer, brief, and output panels. Per-account/session browser preferences restore file, cursor/scroll, side tab, and panel sizes. Source text and undo history are not stored in browser preferences; source is restored from server snapshots, and undo history lasts only while that workspace is mounted. Storage failure falls back to a working default workspace.
- Runner diagnostics shown before raw logs, with expected/actual values where emitted, escaped diagnostic text, and source-line links. Raw logs remain available. Unknown/truncated output is not treated as a passing result, and no names are invented for passing tests. Counts and diagnostics remain runner-reported evidence, not an authoritative grade.
- Eligible opening draft revisions prepare automatically once a connected worker is available. Pending/failed/completed preparation for that revision is not automatically duplicated. Cross-tab automatic requests share a deterministic idempotency key; an existing completed request cannot push a ready session back to preparing. Failed preparation requires an explicit retry. Preparation never starts the timer; editing after preparation invalidates readiness until the new revision is prepared.
- Exercise browsing includes task summaries, editorial difficulty, skills, actual tools, limitations, and a full brief preview before session creation. Ruby execution was unavailable at this historical UI milestone; it is implemented in the curriculum/runner update below. Design diagrams/voice/AI remain unavailable.

The HTML shell moved out of public/ into a controller-served document. Each response carries a fresh CodeMirror style nonce matching its CSP and no-store caching; script origins remain same-origin, and unsafe-inline was not introduced. /index.html does not expose a stale static shell.

Automated checks: **45 Rails runs, 373 assertions, zero failures/errors, two expected opt-in skips**; **7 frontend tests pass** for runner parsing, truncated/error diagnostics, preference sanitization/storage failure, preparation eligibility, and cross-tab request identity. Build and syntax checks pass. Integration checks include nonce rotation/policy matching, preview tool accuracy, and preparation idempotency/readiness.

Browser verification used the existing synthetic preview account. Opened a new timed Rails attempt (`1d73ca3a-d754-4e9f-832a-3538781d531c`) and observed automatic preparation from queued to ready while the timer stayed Not started. Ran the real starter twice (before and after an editor save): each returned 12 real failures. The labeled editor change survived refresh; the new saved revision prepared automatically on reopening. Parsed failures displayed the actual 201/422-versus-501 response differences. Source links opened immutable test files at the correct line with contenteditable=false. Raw output was independently inspectable. Pointer dragging resized output from 240 to 397px; keyboard resizing and refresh restored explorer=210px/output=250px and the selected model at line 2, column 2 in the reference attempt. Tested search controls and file switching. Desktop QA at 1400×900 and mobile at 390×844; mobile document width remained 390px, and its header was repaired after visual inspection. This is focused QA, not an exhaustive accessibility audit.

Screenshots: [failure diagnostics](../../artifacts/workspace-failure-details.png), [prepared without timer](../../artifacts/workspace-auto-prepared.png), [mobile editor](../../artifacts/workspace-editor-mobile.png).

Final editor verification: a fresh reference run through the upgraded workspace returned **12/12 passing, 158 assertions** on the original labeled reference revision. The reference source was not changed. Cursor and vertical scrolling also survived refresh exactly (line 46, column 1; scrollTop 576.5px); returned the editor to the top afterward. No console errors were observed. [Passing editor preview](../../artifacts/workspace-editor-passing.png). The preview assessment remained ready/unstarted throughout QA.

## Maintainability refactor · 2026-10-17

Split the browser entry point into authentication, dashboard, shared API/UI helpers, and an instance-owned workspace with a separate markup module. Centralized presentation rules in `session-policy.js`. Closed screens abort their requests; a transport that ignores cancellation still cannot apply its late reply, including when reopening the same session ID. The API adapter prevents aborted responses from rotating the current CSRF token. Workspace polling is single-flight, skips pending saves/actions, and discards responses from an earlier mutation epoch. Owned dialogs, editor/resize resources, shortcuts, and timers are cleaned up on screen replacement.

Extracted preparation/execution admission into `SessionExecution` and start/submit into `SessionLifecycle`, retaining owner lookup in the controller and existing queue quotas, idempotency, lock order, deadlines, and immutable submissions. Existing integration coverage exercises these service boundaries through the HTTP API.

CSS cleanup removed retired dashboard/marketing selectors and superseded identical-selector declarations while preserving unrelated cascade order. Counts changed from 653 rules / 1,712 declarations to 502 rules / 1,239 declarations. Source JS/CSS is formatted; generated editor assets are excluded. PostCSS was used only for this cleanup and removed afterward; Prettier remains pinned as a development check.

Validation: **45 ordinary Rails runs / 373 assertions / zero failures or errors / two expected opt-in skips**; **17 frontend tests pass**, including state transitions, busy/conflict/read-only controls, stale replies across save/poll/preparation and same-ID reopen, cancellation/CSRF behavior, and the existing parser/preference checks. The separate **real Linux integration passed 1 run / 39 assertions / zero failures, errors, or skips**. Editor build, formatting check, and Rails eager loading passed.

Browser QA: compared layout and computed styles at 1400×900 and 390×844, inspected the existing dashboard/workspace, opened/cancelled the exercise preview, reopened an existing immutable submission/review without editing it, and completed a fresh reference run with **12/12 passing / 158 assertions**. A labeled synthetic QA controller edit was saved by Back navigation, survived reopening the same session, and triggered preparation for the new revision while the assessment timer remained Not started. Existing reference source and review entries were preserved. This is focused regression QA, not an exhaustive visual/accessibility or adverse-network test suite.

Final refactor preview: [workspace](../../artifacts/refactored-workspace.png). The final browser tab showed the original reference session with 12/12 reported passing and no console errors; the temporary viewport override was reset. No production deployment or new infrastructure was introduced.

## Published Rails curriculum and Ruby execution · 2026-10-18

Current ordinary checks: **51 Rails runs, 490 assertions, zero failures/errors, four expected opt-in skips** (three Linux cases and one Railway case). All three Linux cases were then enabled against the actual immutable local image and passed: **3 runs, 192 assertions, no failures/errors/skips**. Railway live execution remains unverified. **19 frontend tests**, **30 Python worker tests**, and **four VM transport tests** pass. Editor build, formatting check, and Rails eager loading pass.

The ordered library now has five Rails repositories, twelve test groups each: Events, tenant authorization, idempotent checkout, retry-safe delivery, and feed performance. New references all pass; twelve intentionally broken Rails variants fail the intended behavioral assertions. New content includes progressive hints, exercise-specific senior criteria/probes/drills, and separately scoped extensions. Ruby intervals version 2 adds six visible and six supplemental groups, including input ownership/generated data and three 100,000-interval cases. Its reference passes all twelve groups/112 assertions; four plausible flawed solutions are caught. Syntax-only preparation does not evaluate the implementation. Version-1 writing attempts remain intact; selection shows the latest published version.

New API checks cover immutable reseeding, read-only test files, hint/review availability on every new exercise, submission-gated references, exact per-exercise prepare dispatch, and an older worker refusing to lease newer exercises. Candidate-facing results remain reported execution evidence; ratings remain explicit self-assessment.

Browser verification used a synthetic guided Ruby attempt (`b1ff7d35-e52a-4a40-925d-dd90085a2828`): starter failure diagnostics, edited labeled reference, save/run, actual 12/12 passing, refreshed source/results, immutable submission, reference reveal, and closing review without modifying ratings. Preview artifacts: `artifacts/ruby-starter-failures.png`, `ruby-runner-passing.png`, `ruby-reference-review.png`. The existing Rails reference/source/review and timed attempts were preserved.

The Rails library shows all five exercises in curriculum order; the new tenant task preview displays its full contract. At 390×844, page width/content are both 390px; the expanded preview dialog is 358px with 356px content. Temporary viewport overrides were reset. Heading rendering was repaired so paragraphs following Markdown headings are not swallowed into the heading. The Ruby Minitest diagnostic parser now handles numbered failures/errors as well as Rails formatting. Browser artifacts: `artifacts/rails-curriculum.png` and `rails-brief-mobile.png`.

## System design canvas and structured notes · 2026-10-18

Published Reliable Webhook Delivery v2 with a native SVG architecture canvas, six structured Markdown sections, and SVG/JSON/Markdown export. The whole artifact set saves as one revision; v1 notes-only attempts remain supported. Timed design starts without an execution worker and uses the existing server deadline. Submission review includes the diagram from the preserved snapshot; no automated architecture judgment is implied.

**56 Rails runs, 544 assertions, zero failures/errors, four expected opt-in skips**. **23 frontend tests pass**. Formatting, bundled editor build, and Rails eager loading pass. New API coverage exercises version selection/legacy compatibility, full artifact persistence, strict graph validation, stale-save conflicts, submission/deadline locking, review evidence from the preserved notes, and owner isolation. New model tests cover invalid identities/endpoints/properties, transactional history behavior, immutable copies, deletion of incident edges, escaped exports, and a static review preview without inline styles or interactive controls.

Browser QA used synthetic guided attempt `4d77984d-03bd-41f2-8171-f8dd440c633d`, explicitly labeled in Requirements as workflow verification rather than personal performance. Created and named three components with responsibilities; added two labeled connections; moved a component using Shift+ArrowDown and restored/reapplied that position with undo/redo; dragged another component; panned blank canvas and used zoom/fit. View changes left the saved revision unchanged. Requirements and Capacity notes persisted alongside architecture after refresh; selected section restored. Markdown now wraps, including in the design notes column.

Real SVG and Markdown downloads were verified: SVG parses as XML with all three components/two connections; Markdown includes the saved requirements/capacity content and all six section headings. Example copies are `artifacts/system-design-example.svg` and `system-design-example.md`. Submitted the sample, confirmed component editing is disabled and the notes editor has `contenteditable=false`, opened the preserved architecture in review, and closed without changing ratings. Browser console warnings/errors were empty.

At 1440×960 the canvas and notes are side by side with the brief to the right. At 390×844 the layout stacks; document content/viewport widths are both 390px and notes width is 390px. Temporary viewport override was reset after QA. Screenshots: `artifacts/system-design-workspace.png`, `system-design-review.png`, `system-design-mobile.png`.

No new service, package, hosted compute, or database migration was required. Voice, conversational interviewing, automated senior feedback, reference architecture libraries, collaboration, and assessment calibration remain separate work.

## Complete interviews and senior curriculum — 2026-10-18

Added support escalation debugging, conditional invoice amendments and safe customer email backfills: 36 new executable groups, tested references, hints, probes and four senior review criteria each. The curriculum now has eight Rails exercises. Three mock interview schedules combine practical work, optional Ruby, system design and seven mixed-source follow-ups with continuous server timing and consolidated review/export.

Validation: **105 Rails tests / 1,316 assertions**, no failures/errors, four opt-in skips; **43 frontend tests**, formatting and eager loading passed; **30 execution-worker tests**; complete real Linux/gVisor suite **3 runs / 330 assertions**, no skips/failures/errors. The browser verified the full debugging plan, source-bound results, immutable submissions, synthetic question answers, reflection persistence and review download. See [the workflow and limits](../../docs/mock-interviews.md). These checks do not calibrate hiring judgments or prove PostgreSQL concurrency/online migration safety.
