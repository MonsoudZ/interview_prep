# Delivery roadmap and release acceptance

## Current boundary

2026-10-17 update: the user selected a local Linux VM for development while retaining their existing Railway hosting. The [Colima/Docker/gVisor setup](../deploy/local-vm/README.md) is now running and the real Rails queue-to-result integration test passes, with browser execution and independent cleanup also observed. See [ADR 003](decisions/003-local-linux-development.md). Historical Linux-unverified statements below describe the earlier milestones; hosted Railway execution, public security validation, voice, Ruby execution, and the design canvas remain incomplete.

Current hosting constraint: Railway only, within the existing budget, with no additional paid services. The Railway Sandboxes adapter is now implemented locally with simulated-provider tests; the next runtime validation requires the intended interview environment, secure credentials, and available-allowance checks before a hosted experiment. Buying a dedicated Linux host is superseded; see [ADR 002](decisions/002-railway-only-budget.md). Hosted execution and isolation remain unverified.

Planning documents were completed before development. The user subsequently authorized the Rails runtime experiment; its local code and measured results are now present. See [results](rails-runtime-experiment.md). No paid service provisioning or deployment has occurred. The milestones below still describe the larger application.

The user then chose our own execution service designed for multi-user growth. Its first [worker implementation](../services/execution_worker/README.md) and [verification record](../services/execution_worker/VERIFICATION.md) are present. See [ADR 001](decisions/001-self-hosted-platform.md). Shared application/queue/voice/review milestones remain outstanding; live Linux isolation has not been validated.

The next application milestone is now implemented locally: [accounts, exercise versions, browser workspaces, snapshots, deadlines, submissions, execution queue, and worker bridge](../apps/platform/README.md). See [verification](../apps/platform/VERIFICATION.md). PostgreSQL/fleet validation, live Linux isolation, advanced workspaces, voice, reviews, and full curriculum remain outstanding.

The practice loop now includes progressive hints for all three representative exercises, persisted assistance history, exercise-specific senior-level self-review, submitted-source references, reflections, and transparent practice suggestions. This is not calibrated AI evaluation. Conversational interviewing, actual Ruby execution, and a design canvas remain unimplemented. The Railway adapter now has a signed queue bridge, checkpoint preparation, bounded execution/cleanup, replay receipts, callback recovery, daily job limits, and an opt-in live Rails integration test. The browser shows execution states and runner-reported test counts with exact source revisions.

The complete release includes all three tracks, voice/text, developed curriculum, reliable workspaces, and rigorous review. Internal milestones allow validation without redefining that release as a basic prototype. No schedule estimate is committed before technical experiments.

## Milestones and exit evidence

| Milestone | Work | Exit evidence |
| --- | --- | --- |
| 0: Planning | Product, experience, contracts, architecture, curriculum, release criteria | Documents agree; open decisions explicit |
| 1: Technical validation | Runtime isolation/startup; Ruby execution; voice interruption; editor sync; canvas serialization; review calibration | Measured experiments, provider choices, estimated usage costs |
| 2: Shared foundation | Private account, versioned exercises, sessions, checkpointing, event streams, conversation | Authenticated text session resumes with exact artifacts |
| 3: Practical engineering | Rails environment, terminal/editor, tests, immutable submissions, revision | Events API completed and reviewed end-to-end with verified reference |
| 4: Ruby interviews | Function runner, examples/tests, follow-ups, Ruby review | Merge-intervals session evaluated across known solutions and defects |
| 5: System design | Canvas/outline, notes, grounded voice interviewer, design rubric | Webhook session supports revisions and evidence-linked critique |
| 6: Depth | Full curriculum, hint progression, calibrated reviews, progress/recommendations | Coverage inventory fulfilled or changes explicitly reviewed |
| 7: Release readiness | Recovery, isolation, accessibility, deletion, budgets, backups | Acceptance matrix passes with recorded evidence |

Voice is developed throughout the milestones and is mandatory at release. Later milestones do not excuse earlier security boundaries or artifact correctness.

## Acceptance matrix

| Scenario | Required result |
| --- | --- |
| New user without mic | Can begin guided practice entirely through text |
| Rails readiness failure | Clock never starts; failure is actionable and retryable |
| Valid/invalid Rails API | Actual tests reflect behavior and expected HTTP contracts |
| Terminal modifies file | Editor receives or explicitly reconciles the new revision |
| Browser refresh | Acknowledged files, diagram, transcript, and server deadline recover |
| Two writer tabs | Explicit read-only/takeover/conflict policy prevents silent overwrite |
| Timeout with pending edits | Graded revision is explicit; late edits preserved separately |
| Runtime outage | Distinct infrastructure outcome; no fabricated candidate failure |
| Ruby boundary/mutation defect | Executed case demonstrates the defect and review cites it |
| Design follow-up | New requirement recorded; original work not retroactively penalized |
| Voice interruption/failure | Speech cancels correctly; text continuation remains usable |
| Review provider failure | Submission stays intact; retry does not create inconsistent grades |
| Evidence link | Opens exact artifact revision and location |
| Valid alternative | Rubric credits justified approach rather than matching reference syntax |
| Hint request | Level recorded; assessment-to-practice conversion is explicit |
| Revision | Original remains immutable; resolved/new findings are distinguishable |
| Recommendation | Cites actual evidence and can be overridden |
| Session deletion | Active artifacts and derived observations removed; backup policy disclosed |
| Runtime isolation attempt | Cannot access another session, host credentials, or private control plane |
| Malicious review instructions | Candidate content cannot reveal solutions or alter grading policy |
| Usage limit | Clear pre-session behavior; no silent mid-assessment resource cutoff |
| Accessibility | Core flows work with keyboard and text alternatives; canvas has structured outline |

## Verification strategy

Use unit checks for state transitions, permissions, revision conflicts, rubric schemas, and rule-based recommendations. Integration checks cover runtime/protocol boundaries and idempotent submission/review jobs. End-to-end checks cover representative sessions and recovery. Use adversarial tests for sandbox and evaluator boundaries. Human-review sample AI outputs rather than asserting exact generated wording.

Content has its own verification: executable references, flawed submissions, stated edge cases, fact sheets, and valid alternatives. A successful test runner is not proof of a calibrated AI review.

## Remaining decisions

Provider/library choices, framework versions, deployment region, operating budget, final interruption policy, and measured performance targets are explicitly deferred to technical validation. Research current official documentation when selecting integrations. Paid provisioning requires an agreed budget and concrete deployment plan.

## Planning completion

This package is complete as a design baseline when product scope, user flows, technical boundaries, representative exercises, curriculum inventory, evaluation approach, delivery dependencies, and release checks are documented. That does not imply implementation or empirical validation is complete.
