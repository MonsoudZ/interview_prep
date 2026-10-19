# Interview Studio — application foundation

A working Rails application with a browser workspace and durable session/execution data. This is a local development milestone, not the completed interview-preparation product or a production deployment.

## Start

To use the configured local Linux worker on this Mac, follow the [VM start/stop guide](../../deploy/local-vm/README.md): `colima start interview`, then `python3 services/local_vm/dev.py start` from the repository root. This starts the app with matching private worker keys. The standalone Rails commands below start only the web application.

Prerequisites: Ruby compatible with the pinned Gemfile (verified locally with 4.0.1), Bundler, SQLite, and the locked gems. PostgreSQL is the production database direction; it has not been tested in this milestone.

From this directory:

```sh
bundle check
ruby bin/rails db:prepare
ruby bin/rails server -b 127.0.0.1 -p 3100
```

If dependencies are missing, install them with `bundle install`. Then open [the local studio](http://127.0.0.1:3100). Development permits creating an account with a password of at least 12 characters. Accounts are stored only in the local development database; no external identity service is used. There is no built-in default account/password.

Production disables registration unless explicitly enabled. Do not deploy this foundation publicly until the deployment gates below are addressed.

## Implemented behavior

- A Progress page with owner-scoped attempt totals, repeated self-reported gaps, rubric-specific rating history, an unfinished review queue, and focused drills persisted into new guided/timed workspaces. Model judgments and runner results do not alter self-assessment ratings. See [the comparison rules](../../docs/progress-tracking.md).
- Revision practice copies a frozen submission into a separate guided/timed attempt with captured feedback, its own execution and review evidence, bounded source comparisons, and design before/after previews. It is explicitly excluded from starter-attempt rating trends. See [revision practice](../../docs/revision-practice.md).
- Scripted follow-up rounds offer guided/timed senior rubric questions after submission, autosaved typed responses, version-protected advancement, deadline enforcement, separate self-checks, transcript export, and resume links in Progress. See [follow-up practice](../../docs/follow-up-practice.md).
- Password-hashed accounts, encrypted session cookies, session expiry, logout, CSRF protection, and local login rate limiting.
- Owner-scoped sessions; another user receives 404 for private resources.
- Immutable exercise versions, with five executable Rails scenarios, Ruby intervals version 2 with an isolated runner, and webhook design notes; older versions remain readable. See the [curriculum](../../curriculum/README.md).
- Guided/untimed and assessment sessions, server deadlines, immutable submissions.
- Multi-file source editing, permitted new Rails files, autosave, explicit save, optimistic revision conflicts, refresh/resume, and read-only exercise assets.
- Immutable source snapshots whose digests match the Python worker contract.
- Durable, revision-bound execution queue with idempotency keys, account pending limits, one active lease per worker, lease expiry, signing, and authenticated result ingestion.
- Worker availability from recent authenticated heartbeats. No worker means queued requests wait; no tests run on the application server.
- Executable assessment start requires successful preparation for the current revision and a recently connected worker. This is a readiness check, not yet a capacity reservation or persistent interactive runtime.
- Browser dashboard/library/history and a workspace showing requirements, source, execution output, revision, and state.
- Three progressive hints per exercise, including an analogous Rails API example. Hints are revealed explicitly, recorded with timestamps, and blocked during assessments and after submission.
- A submission review for all three tracks with exercise-specific senior-level criteria, self-ratings, explanations, and validated references to 1–20 lines of submitted source/notes. Evidence excerpts come from the server's preserved snapshot.
- Saved reflections and practice recommendations based on self-reported gaps, with optimistic review conflicts. Reviews display assistance and only test executions matching the submitted revision; missing execution remains unverified.

The browser uses native modules with a locally bundled CodeMirror 6 editor: Ruby/Markdown/JSON/YAML highlighting, line numbers, search/replace, undo history per file, and read-only exercise/submission views. File explorer, brief, and output panels resize with pointer or keyboard. Selected file, cursor/scroll position, panel tab, and dimensions restore per account/session in this browser; only UI metadata is stored locally. Source remains in server snapshots.

Rebuild the generated editor bundle after changing `frontend/editor.js`:

```sh
npm ci
npm run build
npm test
```

The lockfile pins dependencies. Generated `public/editor.bundle.js` and `public/editor-licenses.txt` ship with the Rails app, so runtime deployment needs no npm/CDN fetch. The HTML shell is served through HomeController with a fresh style nonce for CodeMirror; script restrictions remain same-origin. [CodeMirror API](https://codemirror.net/docs/ref/) documents the editor configuration.

Opening an eligible draft coding session prepares its opening revision automatically when a worker connects; it does not start the timer, retry failed preparation, or execute tests. Matching cross-tab automatic requests share a deterministic idempotency key. Explicit preparation retries use a fresh key. Changes after preparation require preparing the changed revision before an assessment can start.

Test results show parsed failures/errors first, expected/actual values where present, and links into available source files. Raw output is always available; unrecognized/truncated output does not become a fabricated passing verdict. Exercise previews expose the task, editorial difficulty, and available tools before session creation.

Ruby has isolated code execution, visible/supplemental tests, timing, hints, submission self-review, and reference reveal. System design version 2 supports an architecture canvas, six structured notes sections, export, timing, hints, and self-review of the preserved diagram. Local Ollama feedback is integrated with a private pull worker; an actual Studio model still needs installation and benchmarking. Guided/timed rework rounds and saved comparisons are connected. The conversational coach and voice are not connected. Self-assessment is labeled explicitly; the app does not infer a hiring verdict or claim calibrated review accuracy.

Practice: open an exercise in guided mode, reveal support as needed, start the session, and submit. Choose **Review submission** to record what the work demonstrates, attach source lines, save a reflection, and see suggested practice for the gaps you identify. An observed rating requires both a source reference and explanation. **Not observed** stays separate from demonstrated performance.

The current hosting direction is [Railway only, within the existing budget](../../docs/decisions/002-railway-only-budget.md). The [Railway Sandboxes adapter](../../services/railway_worker/README.md) now implements the existing queue/signature/callback protocol and has simulated-provider tests; actual hosted execution is not validated yet. The Linux worker below is optional. No extra paid service is required for the practice/review features.

The execution panel shows queued, starting/running, finished/failed, timeout/output-limit, and infrastructure states. Complete 12-test Minitest output is summarized as **runner-reported** counts. Counts remain tied to the executed revision, with an earlier-revision label after editing. New queued work replaces the displayed output; inspecting an older run stays selected across polling. Counts are not an authoritative grading verdict.

## Connect a Linux execution worker

The application and private Linux worker need distinct random secrets: `INTERVIEW_WORKER_BRIDGE_KEY` for service authentication and `INTERVIEW_WORKER_SIGNING_KEY` for job integrity, each at least 32 bytes. Configure through secure environment mechanisms; do not put them in source files, URLs, command arguments, or chat.

On the worker, also configure `INTERVIEW_WORKER_IMAGE` to the validated immutable image ID. Rebuild the worker image after the new preparation operation was added. Follow the [worker setup and isolation gates](../../services/execution_worker/README.md).

Run the bridge on Linux:

```sh
python3 services/execution_worker/bridge.py --url https://YOUR_PRIVATE_CONTROL_PLANE --worker-id YOUR_CANONICAL_WORKER_UUID
```

This command is run from the repository root, with placeholders replaced. The bridge permits HTTP only for loopback development. It checks Docker/runsc before advertising availability, polls for signed leases, executes with policy limits, persists pending callback deliveries, and posts revision-bound results. Protect its state directory; pending delivery files contain lease credentials.

Routes under `/internal/` require the bridge key and must additionally be private or restricted at the deployment ingress. They use service authentication, not browser cookies. Use dedicated worker identity/key management before a larger fleet; this foundation has shared service keys.

Worker watchdog: run `worker.py reap` independently at least once a minute. Control-plane housekeeping: invoke `WorkerJobs.expire_leases!` and expire overdue interview sessions periodically; request paths also enforce expiry. Failed/expired jobs require an explicit new request, avoiding silent duplicate execution.

## Checks

```sh
ruby bin/rails test
node --check public/app.js
node --check public/practice.js
```

Worker regressions, from repository root:

```sh
python3 -m unittest discover -s services/execution_worker/tests -v
```

The integration tests use synthetic worker callbacks to verify transport/state boundaries. They do not claim a live browser-to-Linux execution or actual grading. A separate test verifies Ruby-signed payloads with the real Python contract.

A separate opt-in [live worker integration test](test/integration/live_worker_test.rb) now exercises actual container preparation, starter/reference tests, callback handling, runtime observations, and submission on a configured Linux host. See the [Linux runbook](../../deploy/linux-worker/README.md). It is skipped by default and has not been run on Linux yet.

## API outline

Browser: GET `/api/bootstrap`; POST `/api/register` or `/api/login`; DELETE `/api/logout`; GET `/api/exercises`; GET/POST `/api/sessions`; GET `/api/sessions/:id`; PUT `.../snapshot`; POST `.../prepare`, `.../start`, `.../execute`, `.../submit`.

Practice: GET `.../practice`; POST `.../hint` with `expected_position` (number of hints already revealed). Assessment/submitted sessions cannot reveal new hints. GET/PUT `.../review` requires a submitted session. Review saves include `expected_version` (null for the first save), an `entries` map keyed by criterion ID, and `reflection`. Each entry contains `rating`, `notes`, and optional `evidence: {path, start_line, end_line}`; observed ratings require evidence. The server derives excerpts and binds the review to the submitted snapshot. Ratings and reflections are self-reported, not machine-verified findings.

Automated feedback: owner-scoped GET/POST `.../automated_review` requires a submitted session. POST accepts a UUID `client_request_id`; repeated requests return the preserved pending/completed review. Offline workers produce no queued job; two pending reviews per account are allowed. Private `/internal/reviews/*` heartbeat/lease/result endpoints use a separate `INTERVIEW_REVIEW_BRIDGE_KEY`. Results must match the leased revision, model digest, and reviewer instructions version. The app validates exact rubric IDs and source/run references before storing a report. See [Studio setup and laptop access](../../deploy/studio/README.md) for local Ollama configuration, private data transfer, and the remaining calibration work.

Mutations require the bootstrap CSRF token in `X-CSRF-Token`. Saves/submissions include `expected_revision`. Execution requests include a fresh UUID `client_request_id`; retry the same work with the same identifier for idempotency.

Worker: POST `/internal/workers/heartbeat`, `/internal/workers/lease`, `/internal/executions/:id/result` with Bearer bridge authentication. A result additionally requires the lease token and matching job/account/session/revision. Completed callbacks are idempotent and cannot overwrite accepted evidence.

## Deployment gates

- Real Linux/Docker/gVisor end-to-end execution, isolation/resource tests, image provenance, and authoritative external grading.
- PostgreSQL migration, concurrency/load verification, per-account storage/runtime budgets, and assessment capacity reservation.
- Shared rate-limit store or ingress limiter; local MemoryStore does not enforce fleet-wide limits.
- TLS/private service routing, per-worker credential lifecycle, ingress request-size/time limits, secrets management, monitoring, scheduled reconciliation, backups, deletion/retention.
- Email verification/password recovery/invites as appropriate before public registration.
- Interactive terminal synchronization, voice/interviewer, rigorous calibrated reviews, and further curriculum depth.

Set `SECRET_KEY_BASE`, `APP_HOSTS`, and a PostgreSQL `DATABASE_URL` for a future production configuration. Those settings alone do not satisfy the deployment gates. No infrastructure has been purchased or deployed.

## Code ownership

The browser entry point `public/app.js` owns screen transitions and unload guards. Screen modules own their own state and cleanup:

- `auth.js`: sign-in/registration UI.
- `dashboard.js`: exercise browsing, session history, and session setup dialogs.
- `workspace.js`: one mounted session's editor, autosave, polling, actions, and preferences; `workspace-view.js` contains its markup.
- `session-policy.js`: pure presentation rules for controls, next actions, and read-only files. Rails still authorizes every transition.
- `api.js`: CSRF-aware fetch adapter; `request-scope.js`: screen lifetime and transport cancellation. An abandoned response cannot update a closed workspace or replace the current CSRF token. Polling is single-flight and ignores responses that predate a save/action.
- `ui.js`: shared stateless labels, icons, escaping, and dialogs. Existing editor, panel, runner-diagnostic, and practice modules retain their focused responsibilities.

Each workspace mount gets an independent closure, even when reopening the same session. Destroying it aborts pending requests and clears its polling/autosave/preference/deadline timers, editor, resize observers, key handler, and owned dialogs. Back navigation awaits saving first.

On Rails, `SessionExecution` owns queue admission, idempotency, quotas, and account/session lock order; `SessionLifecycle` owns starting and immutable submission. `InterviewSessionsController` keeps owner lookup, HTTP input, presentation, and command-error responses. Existing model/worker code remains responsible for expiry and completed preparation readiness.

`public/app.css` is formatted source. Retired design rules and 473 redundant declarations were removed without reordering unrelated cascade rules. Run `npm run format:check` alongside `npm test`; the generated editor bundle is excluded from formatting.

## Expanded curriculum and Ruby execution

Five Rails scenarios now form an ordered path: Events API, tenant authorization repair, idempotent checkout, delivery retries, and activity-feed performance. Every new repository has 12 executable tests, a full brief, three hints, targeted senior criteria/drills, and a tested reference. Ruby intervals v2 runs six visible and six additional test groups, including generated, ownership, and 100,000-interval cases. Version-1 writing sessions are preserved; new selection uses the latest version. Reference solutions are owner-scoped and available only after submission through the review dialog.

The worker advertises only operations present in its immutable image. Specific prepare operations prevent an Events-only worker from leasing unrelated scenarios. Code/paths and signatures remain bounded; candidate source never executes on the app server. See [curriculum validation](../../curriculum/README.md) and [local VM verification](../../deploy/local-vm/VERIFICATION.md). Existing Railway sandbox checkpoints advertise only their installed Events operation; expanding the local image does not silently expand hosted capabilities.

## System design workspace

Reliable Webhook Delivery v2 opens a native SVG canvas beside structured Markdown sections: Requirements, Capacity, APIs & data, Reliability, Tradeoffs, and Handoff. Add/name components, describe responsibilities, label directed connections, move components with drag or arrow keys (Shift for larger moves), pan blank canvas, zoom/fit, and undo/redo architecture changes. Each section retains its editor history while mounted; Markdown wraps for reading. Export SVG, diagram JSON, or all notes as Markdown.

The diagram and all six sections save in one source snapshot/revision. Timed design sessions start explicitly without an execution worker; normal server deadlines, optimistic conflicts, and immutable submissions apply. Design review displays a static diagram generated from the submitted snapshot, and its evidence references can cite any preserved notes/diagram file. No test counts or component-presence heuristic imply architecture correctness. Version-1 writing attempts remain unchanged.

Only bounded, validated diagram JSON is stored (50 components, 100 connections, approved kinds, unique IDs, finite coordinates, bounded text, existing endpoints). There is no user-supplied SVG or external image/script source. The review preview uses the existing stylesheet under the strict CSP. See [the design workspace contract](../../curriculum/system_design/README.md).
