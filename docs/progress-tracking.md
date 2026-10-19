# Progress tracking

Implemented 2026-10-18. Open **Progress** in the sidebar or `/#progress`. This feature works without a Studio model connection.

## Evidence and comparisons

Progress reads only the signed-in account's submitted attempts and saved self-assessments. A criterion is observed when its rating is one of `needs_development`, `approaching_target`, `meets_target`, or `exceeds_target`. Missing entries and `not_observed` are unassessed. A partial review can count as having a self-rating while still appearing in the unfinished review queue.

Revision-practice attempts are labeled reworks in attempt history and the review queue. Their ratings stay out of starter-attempt trends and active gap resolution. Compare their ratings separately against the saved source review through [revision practice](revision-practice.md).

The Follow-up rounds section provides resume/view links for the ten most recently updated scripted interview rounds. Their answer counts and self-checks stay separate from source-review criteria, starter-attempt gaps, and submitted coding/design totals. See [follow-up practice](follow-up-practice.md).

One criterion contributes one observation per submitted attempt. Editing a saved review replaces that observation. Order follows submission time, so editing an old review does not make it the latest attempt. Review rubric versions and submitted snapshot identities must match before ratings contribute.

Comparisons use exercise slug, rubric version, and criterion ID. There is no aggregate skill score or cross-exercise equivalence inferred from similar names. A higher/lower label compares the latest two observed self-ratings; guided/timed mode and revealed-hint counts remain visible. Once the current rubric has an observation, older rubrics stay in history and leave the active plan without being marked resolved.

## Practice plan

The latest observed rating determines whether a criterion remains an active self-reported gap. A repeated gap has at least two below-target observations and its latest observation is still below target. A later target rating removes it from the active plan; that is a change in self-assessment, not a verified mastery claim.

Priorities are deterministic: repeated gaps first, then number of gap observations, latest rating, submission recency, and a stable criterion key. The page shows up to three priorities for the selected track. Each includes the published exercise-specific drill and the source review. A newer unfinished focused attempt is resumed; a newer submission is offered for review before another drill. Submitting a focused attempt alone does not resolve the gap.

Starting a focus uses the normal exercise setup with either guided or timed mode. The client sends only the source session ID and criterion ID. The server verifies ownership, a submitted same-exercise source, and an active below-target source rating, then derives and saves the focus title/drill from the published rubric. Arbitrary client instructions and unrelated or resolved source criteria are rejected. The focus stays visible in the new workspace brief and survives reloads. If the target exercise version changes, the plan labels that transition; its later rubric observations stay separate.

## Review queue and attempt history

Unfinished reviews include every submitted supported attempt with at least one unassessed criterion. They are ordered newest first; the UI shows up to ten for the selected track. Direct actions open the preserved submission review, and returning to the studio retains the Progress page.

Recent history shows the latest 20 submitted attempts across tracks. Criterion histories show their latest eight observations; aggregate counts include the full account history, including attempts beyond the ordinary Sessions screen's 100-row window.

Runner summaries are shown separately and only from test requests matching the submitted revision. Missing or truncated output produces no passing conclusion. Candidate-controlled output is labeled reported evidence. Model feedback never changes self-assessment progress. Design attempts are reviewed from their diagram and reasoning rather than test counts.

## Verification

Nine Rails integration tests cover account isolation/login, repeated gaps, edit ordering, latest-rating changes, unobserved criteria, rubric changes, 105-attempt aggregation, focus persistence and ownership, malformed focus requests, revision-bound execution, model/self-rating separation, and expired assessments. Four frontend tests cover escaping, track filtering, resuming focused work, and incomplete runner evidence.

Browser checks use the existing preview account's clearly labeled verification attempts. No new performance rating or practice attempt was created in that account during this milestone. Checks covered direct review opening, return navigation, focused setup, track filtering, reloads, and a 390-pixel mobile viewport with no horizontal overflow. The temporary viewport override was reset.
