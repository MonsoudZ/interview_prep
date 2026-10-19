# Published practice curriculum

The Rails path is a progression, rather than a collection of interchangeable CRUD prompts:

| Order | Exercise | Time | Repository starting point | Focus |
| --- | --- | --- | --- | --- |
| 1 | Repository Events API | 50 min | Minimal API stub | Routes, validation, HTTP contracts |
| 2 | Repair Tenant Authorization | 55 min | Working but unsafe API | Trace unfamiliar code; protect reads and writes |
| 3 | Idempotent Inventory Checkout | 65 min | Stub with supplied tables | Replay, rollback, database invariants |
| 4 | Retry-Safe Delivery Job | 60 min | Supplied job and fake transport | State transitions, durable attempts, duplicate jobs |
| 5 | Repair a Slow Activity Feed | 60 min | Working but slow/leaky endpoint | Cursor boundaries, N+1 queries, bounded loading |

Each Rails repository has twelve visible executable test groups, three progressive guided hints, four exercise-specific review criteria (five in the original Events exercise), interview probes, gap-based drills, a tested reference implementation, and a separately scoped senior follow-up. Times/levels are editorial estimates; they have not been calibrated against candidate cohorts.

Start with guided practice, read the files/tests, and implement one vertical slice at a time. Hints illustrate analogous patterns and are recorded as assistance. Repeat in assessment mode on a fresh attempt when you can reconstruct the patterns. Reference files open in submission review only after submission. They show one valid approach, not a mandatory architecture. Self-review ratings require evidence in the submitted revision; they are not AI or hiring decisions.

## Structure and immutability

The original Events assets remain in `experiments/rails-runtime`. New Rails exercises live under `rails/<slug>/`:

- `exercise.json`: published identity, execution operation, editorial metadata.
- `starter/`: supplied repository overlay and complete task contract.
- `reference/`: tested solution overlay, never seeded into candidate files or staged into the VM.
- `review.json`: hints, criteria, probes, next drills, and extension.

`db:seed` combines each starter with the pinned shared Rails template. Versions are immutable. Future published changes require a new version; do not silently rewrite sessions/snapshots. New session selection shows the latest version of a slug; existing sessions retain their original version. Tests, boot files, and dependencies are read-only in the editor. Candidate edits remain subject to the runner path allowlist.

Worker dispatch maps signed versioned operations to fixed trusted runner arguments. Bridges advertise only operations present in the configured immutable image; an older Events-only image cannot claim the expanded curriculum. Preparation is dispatched per exercise and never starts an assessment timer.

## Ruby execution

`ruby/merge-intervals` publishes executable exercise version 2; saved version-1 writing attempts remain intact. The sandbox runs six visible and six supplemental contract groups in one twelve-test suite, including deterministic generated cases, frozen input, and 100,000-element cases. Supplemental fixtures are omitted from the editor; they are not security secrets from code executing in that sandbox. Failure messages identify categories without dumping large fixtures. No assertion goes beyond the published contract.

Prepare compiles Ruby syntax without evaluating the solution. Only solution.rb is writable. Test execution uses the existing non-root gVisor/no-network container and 60-second outer bound. Output/counts are candidate-influenced execution evidence, not an authoritative grade. Timeouts and memory/output limits are reported as execution outcomes, not a measured complexity classification.

## Validation

For **trusted published fixtures only** (never user snapshots), run:

```sh
python3 curriculum/rails/validate.py --mutations
python3 curriculum/ruby/validate.py
```

The scripts stage temporary repositories, verify readiness/starter failures/reference success, and check intentionally flawed solutions. Rails mutations include missing tenant scoping, missing role enforcement, mass assignment, unscoped idempotency, missing transaction/index, resending terminal jobs, misclassifying 429, swallowing programming exceptions, N+1 author queries, and per-post count queries. Ruby mutations cover shrinking nested intervals, missed touching endpoints, input mutation, and skipped sorting. JSON reports record actual results. These host-side checks evaluate only repository-owned trusted fixtures; candidate execution stays in Linux.

The opt-in platform `LiveWorkerTest` exercises real authenticated queue leases/callbacks, each published Rails starter/reference, Ruby execution, revision identity, isolation observations, and immutable submissions. Run Rails test processes sequentially against SQLite; concurrent test processes share a database and can contend. See `deploy/local-vm/VERIFICATION.md` for the actual image and results.

Concurrency of checkout under production PostgreSQL, simultaneous job claiming, crash-window remote idempotency, production query plans, cohort timing calibration, public hosting, and automated senior reviews remain separate work. Those boundaries are stated in the relevant briefs rather than retroactively required in reviews.

## System design workspace

Reliable Webhook Delivery version 2 publishes a canvas plus six structured notes sections with the existing requirement sheet, six senior criteria, progressive hints, and outage follow-up. Architecture and notes are preserved together; submission review includes the diagram from that revision. See [the workspace contract](system_design/README.md). Existing notes-only v1 attempts remain intact. Voice, live conversational interviewing, automated architecture analysis, and reviewer calibration are still separate work.
