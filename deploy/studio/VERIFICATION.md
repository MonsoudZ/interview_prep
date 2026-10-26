# Studio integration verification

## Calibration of two recurring evaluator flags — 2026-10-26

Same Studio and model digest (`qwen3.5:27b`, `sha256:2d2e4b8fc7c0…`), prompt `senior-review-v8`, reasoning mode with fall back, `--repeats 2`. Reports are under ignored `artifacts/reviewer-evaluation/lru-nil-wording-001` and `-002`. No practice history was written.

Two flags that recurred across prompt versions were traced to the published text and a fixture expectation rather than to the reviewer; the reasoning is in the evaluator README's "Calibration decisions" section.

- **LRU `boundaries` leak.** The version-1 brief and probe could be read as requiring `get` to let callers distinguish a stored `nil` from an absent key, while the reference returns `nil` in both cases and no test asks for more. Published `ruby/lru-cache` version 2 with an unambiguous brief, `boundaries` target, probe and practice (`ruby-lru-cache-review-v2`); tests, reference and the `ruby.lru-cache.v1` operation are unchanged, so no image rebuild. Version 1 is archived under `versions/1/` and `RailsCurriculum` resolves it for existing sessions; a new integration test covers that path.
- **Tenant projects `authorization` leak.** The planted scope widening makes a viewer requesting another tenant's ID receive 403 where the brief promises 404, and the `authorization` target includes ownership resolution preceding role checks. That is a consequence of the planted line, so `authorization` is no longer listed as independent for the defect variant (the reference variant still requires all three source criteria at target).

Live check on the LRU pair after the wording change:

| Run | Case | Attempt | Mode used | Seconds | Output tokens | Result |
| --- | --- | --- | --- | --- | --- | --- |
| 001 | LRU reference | 1 | reasoning | 262 | 6,343 | clean |
| 001 | LRU reference | 2 | reasoning | 498 | 6,203 | clean |
| 001 | LRU defect | 1 | reasoning | 609 | 7,631 | defect found and cited; `boundaries` lowered because the first draft of the version-2 target said a stored `nil` is "refreshed by `get`" |
| 001 | LRU defect | 2 | reasoning | 490 | 6,015 | same as attempt 1 |
| 002 | LRU defect | 1 | reasoning | 432 | 5,764 | defect found and cited, no leaked criteria; report rejected by the contract because one citation spanned 27 lines (the cap is 20) |
| 002 | LRU defect | 2 | reasoning | 527 | 5,156 | clean |

The sentinel demand did not appear in any of the six attempts; every `boundaries` rationale now states that returning `nil` for both cases is the contract. The run-001 defect leak was a correct reading of overlapping criteria that the first draft introduced, so the published `boundaries` target leaves recency refresh to `correctness` explicitly; run 002 is the text that was committed. Four reasoning attempts stayed within budget this time (no fall back), at seven to ten minutes each. Two attempts per case remain a small-sample repeatability observation, not evidence that the leak cannot recur, and the tenant-projects pair was not rerun here.

Also run: `build_packets.rb` (LRU packets now carry exercise version 2), the Rails suite (130 runs, 1,732 assertions, zero failures, four expected opt-in skips), the 18 review-worker Python tests, and `curriculum/ruby/validate.py` (validation report unchanged).

## Real-model setup — 2026-10-21

Verified on the 64 GB Apple M4 Max Studio with Ollama 0.40.6:

- Installed `qwen3.5:27b`, digest `sha256:2d2e4b8fc7c0479b70f8cba9fc8bdb49a3c9a43a8a6da3873b724c9fca4672ef`. Ollama reported the MLX runner, 100% GPU, approximately 20 GB loaded, and a 32,768-token context. This is a loaded-size observation, not a peak-memory benchmark.
- Configured private app/reviewer credentials and started `python3 services/local_vm/dev.py start --review-only`. The app returned HTTP 200 and the database showed a recent authenticated heartbeat for the installed model. Colima and the Linux execution worker are not configured on this Studio.
- Ran real inference through the existing provider, schema, and prompt using the repository's LRU reference source, separately from user practice history. The initial v1 result took 69.7 seconds and failed server validation: it categorized missing logs as an execution observation without an execution ID. It also penalized correct source solely because runs were absent.
- Versioned the clarified evidence instructions as `senior-review-v2` in both app and worker. The reference rerun took 48.1 seconds (2,098 input / 1,043 output tokens), produced no findings, rated the three source criteria `meets_target`, and left candidate testing-process evidence `not_observed`. The actual Rails report validator accepted it.
- A second v2 check removed the recency update from `get`. In 60.4 seconds (2,088 input / 1,370 output tokens), the model identified that defect and the actual Rails report validator accepted the report. It also added an unsupported preference for linked lists and conflated recency correctness with complexity. These remaining semantic issues mean this is not a calibrated reviewer.
- Passed 3 review-only launcher tests, 2 Studio transfer tests, 7 review-provider/transport tests, and 7 Rails automated-review integration tests (126 assertions). Diff whitespace checks passed.

Local setup evidence is under ignored `artifacts/model-validation/`: reference and mutated packets, raw reports, the original rejected v1 report, and the smoke script. No synthetic practice submissions or self-ratings were written to the user's development history. These checks establish direct provider inference, report validation, and app/worker connectivity; they do not establish a complete real-model browser-to-queue-to-callback review, Rails/design model accuracy, repeated-run consistency, or held-out calibration. The two LRU examples were setup checks and must not be counted as held-out evaluation.

## Public guidance and reasoning mode — 2026-10-21

Same Studio, same model digest, prompt `senior-review-v3` with the public guidance catalog `public-interview-guidance-v2`, using the local evaluator's six fixtures (reference and planted-defect pairs for the LRU cache, the rate limiter, and a durable-intake design note). Reports are under ignored `artifacts/reviewer-evaluation/`. No practice history was written.

Fast setting (`think: false`), four Ruby cases, 50–90 seconds each: the LRU reference's complexity criterion was downgraded for using two hash operations and for missing logs, contrary to the instructions; the LRU defect was found but lowered the independent complexity and boundary criteria too; the rate-limiter defect (strict `>` where the brief requires `>=` expiry) was missed entirely, with the report asserting the operator matched the brief. The rate-limiter reference was clean.

Reasoning setting (`think: true`): LRU reference clean in 230 seconds (5,685 output tokens); rate-limiter reference clean in 221 seconds; rate-limiter defect identified with the contradiction of the brief stated, but cited line 20 instead of the actual line 28; durable-intake defect identified and cited correctly in 182 seconds. The LRU defect and durable-intake reference cases exhausted a 14,000-token output budget after roughly nine minutes each and produced no report.

Changes made from these results: reasoning mode is the default for new configurations, with the budget set at 10,000 output tokens (successful runs used 4,700 to 8,400) and an automatic fall back to the fast setting when the budget is exhausted, recorded as `reasoning: 0` in the saved usage and shown in the review's provenance. Worker heartbeats now extend the running review's lease, capped at twenty minutes from the lease. Prompt `senior-review-v8` adds literal operator comparison against the brief, says that returning exactly what the brief specifies is never a gap (fast-mode reports repeatedly demanded a sentinel so `get` could distinguish a stored nil from an absent key), states that packet.files is the candidate's submission and that design notes plus diagram are the design (a v6 fast-mode run reported that nothing was submitted for both design fixtures and rated everything not_observed), states that rubric probe and practice fields are questions rather than requirements (a v5 reasoning run downgraded the correct LRU reference for the nil-handling probe), and the worker now shows the model each submitted file with `N| ` line prefixes (presentation only; the stored packet is unchanged) because both reasoning and fast reports cited lines one to eight short of the real ones when asked to count. The evaluator now records author-specified semantic flags per case (missed defect, uncited defect, leaked criteria, unsupported downgrades, process criteria rated without evidence, execution observations without runs) and can rescore an existing run.

Partial check of the fall back with prompt v4 (stopped after two cases once v5 superseded it): the LRU reference was clean in 283 seconds using 7,029 output tokens, and the LRU defect exhausted the 9,000-token reasoning budget, fell back, and completed in 417 seconds total with the defect identified, no leaked criteria, and citations one line short.

Full six-case run, reasoning mode with fall back, prompt `senior-review-v7` (v8 differs from it by one sentence about stated return contracts, verified only in the fast run below):

| Case | Mode used | Seconds | Semantic flags |
| --- | --- | --- | --- |
| LRU reference | reasoning | 257 | clean |
| LRU defect | fell back after budget exhaustion | 468 | defect found and cited; boundaries also lowered (sentinel demand) |
| Rate limiter reference | reasoning | 212 | clean |
| Rate limiter defect | reasoning | 243 | defect found and cited; memory and boundaries also lowered |
| Durable intake reference | fell back after budget exhaustion | 419 | clean |
| Durable intake defect | reasoning | 368 | clean |

Full six-case run, fast setting, prompt `senior-review-v8`, 33–82 seconds per case: the LRU reference's complexity criterion was again lowered for missing execution logs; the LRU defect was found but boundaries was lowered for the same sentinel demand; the rate-limiter defect was missed again with boundaries lowered by a vague reference to it; the rate-limiter reference and both design cases were clean.

Reading across runs: reasoning mode has never missed a planted defect in these fixtures, while the fast setting missed the rate-limiter boundary in every attempt and keeps inventing a nil sentinel requirement. Reasoning mode exhausted its budget in two of six cases per run (which case varies between runs with the same prompt and temperature 0), and the same prompt text produced different leakage on repeat runs, so one run cannot confirm or refute a prompt change; expect three to eight minutes per review and read the leaked-criteria flags as a known residual weakness.

These remain six author-written regression fixtures that have now been used to tune the prompt and the mode; they are not held-out evidence of accuracy on new submissions, Rails exercises, or real candidate explanations.

## Historical integration checks — 2026-10-18

Completed on the existing development Mac, **not on the user's M4 Max Studio**:

- Rails suite after the follow-up practice milestone: **90 runs, 1,057 assertions, zero failures/errors; four expected opt-in skips**. Includes seven automated-review integration tests (126 assertions): submission ownership, offline behavior, quotas, request deduplication, private gateway authentication, lease expiry, revision/model identity, strict rubric IDs, source excerpts, execution references, and preserving self-assessment. Nine follow-up tests add 168 assertions for saved question flow, deadlines, stale writes, self-checks, quotas, immutable answers, and ownership. Nine rework tests add 131 assertions for copied/frozen source, feedback, timers, quotas, comparisons, and account ownership. Nine progress tests add 88 assertions for owned history, comparable rubric observations, 105-attempt aggregation, persistent focus, stale/resolved focus rejection, and runner/model separation.
- Frontend suite: **37 tests passed**. Includes escaping model text/citations, keeping source concerns distinct from recorded runner observations, track filtering, focused-attempt actions, and incomplete execution evidence. See [Progress verification](../../docs/progress-tracking.md).
- Python local-model tests: **six passed**. Five provider checks plus an actual loopback HTTP transport test running the worker subprocess against synthetic app/model servers. This verified heartbeat, lease, frozen packet delivery, structured inference request, Ollama's unprefixed digest normalization, callback identity, private callback receipt cleanup, and one inference request. No actual language model was invoked. Scripted typed follow-up rounds are a separate application feature, not model inference.
- Studio transfer tests: **two passed**. SQLite backup includes committed WAL data, uses private permissions, and refuses overwrite; restore preserves submitted artifacts and refuses an existing account/session database. Code packaging excludes private state, databases, environment files, credentials directories, caches, and symlinks.
- Browser check: submitted system-design review displays **Studio reviewer offline** with generation disabled and the existing self-assessment available. No synthetic model review was stored in the user's practice history.
- Development and test database migrations applied. Rails eager loading passed. No execution-worker isolation policy changed; earlier real gVisor execution verification is documented separately in the [VM verification](../local-vm/VERIFICATION.md).

Not verified: Studio installation, real Ollama inference, actual model latency/memory, semantic review accuracy, human-reviewed calibration, remote SSH access, PostgreSQL concurrency, public hosting, automatic login/startup services, or background operation across sleep. No paid model fallback or Railway compute was provisioned.

The initial model candidate is `qwen3.5:27b`. Its selection is provisional until measured against Rails, Ruby, and system-design examples on the Studio. Report validation establishes structure and provenance, not correctness of the model's conclusions.

## Expanded curriculum and complete interview milestone

- Rails: **105 runs, 1,316 assertions, zero failures/errors, four expected opt-in skips**. Fifteen mock-interview integration tests cover schedules, readiness, deadlines, ordered transitions, ownership, frozen source, late follow-up writes, review provenance, focused drills and standalone trend separation.
- Frontend: **43 tests passed**; formatting and Rails eager-loading checks passed.
- Execution worker: **30 Python tests passed**, including capability inventories that prevent an older image from advertising new exercises. All published Rails fixtures passed preparation/reference validation and all 18 deliberate defect mutations failed behavior checks.
- Actual Linux/gVisor integration on the laptop: **3 runs, 330 assertions, zero failures/errors/skips** on the rebuilt `rails-ruby-v2` image. Includes all eight Rails exercises, Ruby, isolation observations and real queue callbacks. See the [VM verification](../local-vm/VERIFICATION.md).
- Browser: completed the debugging/design/follow-up sequence, received the new support reference result (12 tests/65 assertions), verified immutable source, saved/reloaded the overall reflection, and downloaded a consolidated review with both source identities and answered/partial/unasked states. A 390px responsive check had no horizontal document overflow. Verification sources/reflection are labeled synthetic; no personal ratings were recorded.

The new app features do not require Ollama. The Studio model installation and semantic reviewer calibration remain outstanding.

## Follow-up answers as process evidence — 2026-10-21

Same Studio and model digest, prompt `senior-review-v9`, reasoning mode, two new evaluator cases that add a completed follow-up round's typed `verification` answer to the LRU reference packet (`follow_up_answers` plus a citable `follow-up/verification.md`). Reports are under ignored `artifacts/reviewer-evaluation/followup-answers-001/`. No practice history was written.

| Case | Seconds | Output tokens | Semantic flags |
| --- | --- | --- | --- |
| LRU follow-up correct | 207 | 4,918 | clean: `verification` meets_target citing `follow-up/verification.md` lines 1–4; three source criteria meets_target; no findings |
| LRU follow-up contradicts | 342 | 8,396 | `verification` needs_development citing lines 1–2 of the answer, with the contradiction of the code and the tests-first claim both stated; `correctness` and `complexity` unchanged; `boundaries` lowered to approaching_target by the same stored-nil sentinel demand already seen in the v7 and v8 runs (`leaked_criteria`) |

The answer evidence worked as intended in both directions: a process criterion that was always `not_observed` is now rated from the cited answer, and a wrong answer did not change the correctness rating of the correct source. The boundaries leak is a pre-existing fast-and-reasoning failure mode unrelated to the follow-up change and remains open.
