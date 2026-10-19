# Complete mock interviews

Open **Mock interviews** in the application navigation. Plans combine existing versioned workspaces into one owned interview record. This feature works without a model or voice service; follow-up questions are scripted from the published rubrics.

| Plan | Stages | Total budget |
| --- | --- | --- |
| Senior backend interview | Invoice amendments (60m), Ruby intervals (35m), webhook design (40m), mixed follow-ups (14m) | 149 minutes |
| Debugging and architecture | Support escalation repair (40m), webhook design (35m), mixed follow-ups (14m) | 89 minutes |
| Data migration and architecture | Customer email backfill (60m), webhook design (40m), mixed follow-ups (14m) | 114 minutes |

Budgets are editorial practice settings, not calibrated hiring thresholds. Mock stage budgets can differ from standalone exercise durations; the workspace displays the captured stage budget. Prior exposure to tasks, reference solutions or published probes can make repeat attempts less representative of an unfamiliar interview.

## Preparation, timing and resume

Booking captures the exact exercise versions, order and budgets. Only the first workspace is created. Its executable environment must prepare successfully with a connected capable worker before Start session is accepted. Preparation does not consume interview time. Mock source editing and test execution remain locked until the stage starts.

Starting that first stage starts both its stage timer and the overall interview timer. Later stage deadlines are the earlier of the stage budget from its start and the overall deadline. Transitions, navigation, disconnections and closed tabs consume overall time. There is no pause button. A browser clock is informational; Rails enforces every deadline.

Submit a workspace, return using **Interview** in its header, then choose **Continue to next stage**. Future workspaces stay locked until the server accepts that transition. After the question round, choose **Complete interview**. Resume from the saved interview list or `#interview/<id>`; source workspaces and question rounds also have direct resume links.

Stage expiry submits the last saved revision. Overall expiry freezes any created workspace and the last saved follow-up draft; unopened or never-started stages are recorded as unattempted. Finish interview early does the same immediately. Local text that failed to reach the server is not silently included in a submission. The existing editor and question tools preserve such local text for recovery.

## Cross-exercise follow-ups

The final stage captures seven questions across the submitted practical/Ruby/design sources and one design extension within that set. Two-source plans take three rubric probes per source plus the extension; the full three-source plan takes two per source plus the extension. Each captured question records the exact source session and submitted revision. All sources must already be submitted. Question guidance stays hidden until the round ends.

The round is always timed and cannot switch to guided mode. Its deadline is capped by the overall deadline. Existing autosave, sequential answer locking, explicit skips, partial answers, resume, separate self-checks and transcript export apply. Standalone follow-up creation on an unfinished mock's source is blocked; use the canonical interview stage instead.

## Consolidated review

The completed interview presents every stage together, with expandable evidence and links back to its source review or follow-up transcript. It includes:

- Frozen submitted revisions and stage timing.
- Up to five recent test runs from that exact submitted revision, labeled as reported execution evidence. Earlier-revision runs do not count as current results. System design uses architecture/notes evidence rather than a missing-test warning.
- Saved source-bound self-assessment entries matching the submitted snapshot and current published rubric. Missing ratings remain unobserved.
- Availability of completed advisory model reports for the same revision, opened within the original submission review.
- Follow-up answer states, source provenance, independent self-checks and reflection.
- Focused drills derived from recorded source-review gaps or follow-up needs-practice self-checks. No gap is invented from missing ratings.
- An independently saved overall reflection and downloadable plain-text interview review.

Tests, self-assessments and advisory model feedback remain separate. No numerical aggregate, hiring verdict, or claim of FAANG calibration is produced. Stage self-assessments can be updated later; Refresh evidence recomputes the consolidated view without changing submitted work. Mock stages appear in session history and review queues with a label, but do not alter standalone starter-attempt progress trends.

## Persistence and admission

`mock_interviews` owns the schedule and overall clock. `mock_interview_stages` pins exercise identities and uniquely links the sequentially created sessions/round. Existing snapshot, execution and follow-up models remain authoritative for source and answers. Creation is idempotent per account/request UUID; reusing a UUID for another plan conflicts. Optimistic versions protect parent transitions and reflection edits. Deadline completion persists even if a late or stale command is rejected.

An account may have two unfinished mock interviews. The existing ten unfinished workspace and two unfinished follow-up quotas also apply when provisioning stages. Ownership is checked through the account for every parent and child endpoint. No accounts, interviews or transcripts are included in Git or code transfer packages.

## Verification

Integration coverage exercises all three plans, exact version/budget capture, first-stage readiness, one-time clock start, lazy provisioning, stale transitions, stage/global deadlines, late snapshots, early finish, multiple source question provenance, forced timed mode, same-revision tests, independent self-assessments, focused drills, standalone progress separation and account isolation. Frontend tests cover locked controls, escaping, evidence labels, export provenance and avoiding clock-only polling rerenders.

The browser verification interview is explicitly labeled in its source and overall reflection as a synthetic product test. It uses a published Rails reference, minimal design notes and synthetic answers; its 12/12 runner result is not a claim about the user's performance. Export and screenshots are local ignored artifacts.
