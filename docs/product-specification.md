# Product specification

## Purpose and audience

Prepare one user for senior Rails/backend interviews, with room to support additional users later. The user recognizes Rails patterns but needs examples to implement them independently. Learning support must address this baseline while assessment rubrics retain an explicit senior-level bar.

The intended product is a hosted web application with developed experiences across all three tracks. Rails receives particular curriculum depth. Implementation phases are checkpoints, not a reduction of the agreed product scope.

## Tracks

1. Practical Rails: minimal-repository APIs, existing-code features, debugging, refactoring, queries, data integrity, background jobs, integrations, and concurrency.
2. Ruby challenges: algorithms, data structures, explanation, complexity, testing, and changing constraints.
3. System design: component drills, detailed API/data design, full architecture, failure handling, and design revisions.

Behavioral interviews and project deep dives are subsequent tracks.

## Modes

| Mode | Support | Timing | Feedback |
| --- | --- | --- | --- |
| Worked lesson | Complete examples and explanations | Untimed | Throughout |
| Guided practice | Examples, checklists, progressive hints | Optional | On request |
| Independent drill | Hints on request | Optional | After attempt |
| Assessment | Clarification and interviewer follow-ups; no coaching | Fixed | After submission |
| Revision | Findings and targeted help | Usually untimed | Changes reviewed |

Hints progress through nudge, concept explanation, analogous example, and guided implementation. Record help use without treating learning assistance as failure.

## Navigation and workspaces

- Home: resume a session or start a recommendation with an evidence-based reason.
- Learning path: prerequisites, supported practice, and independent checkpoints.
- Library: track, skill, difficulty, duration, and format filters.
- Briefing: complete requirements, assistance rules, environment status, deadline policy.
- Coding workspace: file explorer, tabbed editor, terminal, test output, requirements, conversation, timer, and submission.
- Design workspace: canvas, labeled components/connections, requirements, estimates, API/schema notes, and conversation.
- Review: prioritized verdict, evidence-linked findings, artifacts, transcript, reference approaches, and revision.
- Progress/history: skills, independence, prior attempts, and saved sessions.

Panels resize/collapse. Code autosaves with visible save status. Revision creates a new artifact branch/snapshot; the original submission remains immutable.

## Voice and interviewer behavior

Voice and text are first-release requirements in all tracks. Support interruption, mute, transcript correction with an audit trail, and switching to text. Persist work through connection failures.

The coach offers requested support. The interviewer allows thinking time, asks one clear question at a time, probes actual work, and withholds coaching during assessments. Clarification, assistance, and new follow-up requirements are recorded distinctly.

Audio retention is optional and configurable. Provide session deletion. Do not use accent, facial expressions, or silence as proxies for technical ability. Camera recording is a possible later feature.

## Evaluation

Assess correctness, reasoning, judgment, implementation quality, relevant reliability concerns, communication, and independence. Rubrics are task- and level-specific. They approximate a demanding senior interview bar, not a guaranteed company hiring decision.

Tests determine execution results. AI cannot override them. Findings distinguish verified defects, concerns, and optional refinements. Every finding cites code, execution, transcript, or a diagram element and explains consequence and remediation.

Review submitted results and demonstrated understanding separately. Recognize valid alternative solutions and constraints imposed by time. Do not penalize missing architecture unrelated to the task.

Reviews include confidence/limitations, supported strengths, prioritized findings, counterexamples where executable, reference alternatives, follow-up questions, a revision, and two or three targeted next actions.

## Curriculum and progress

Track introduced, assisted, independent, and timed demonstrations per skill. Fresh variants provide stronger evidence of transfer than repeated memorization. User can override recommendations.

Planning target: approximately 24 Rails, 24 Ruby, and 12 system design exercise packages, subject to quality and coverage. Each package has versioned requirements, starter artifacts, rubric, hints, reference approaches, and verified tests where appropriate. Validate generated variants before scored use.

## Proposed architecture

| Component | Responsibility |
| --- | --- |
| React/TypeScript frontend | Editor, canvas, audio, transcript, workspace |
| Rails backend | Accounts, exercises, sessions, authorization, orchestration |
| PostgreSQL | Structured application records |
| Object storage | Snapshots, diagrams, exports, optional audio |
| Background workers | Preparation, grading, reviews, content validation |
| Runtime service | Isolated Rails/Ruby execution |
| AI/voice adapters | Conversation, transcription, speech, evaluation |

Providers, versions, deployment design, and cost estimates require technical validation before adoption.

## Records

PreparationProfile, Skill, Exercise, ExerciseVersion, Session, WorkspaceSnapshot, SessionEvent, ConversationTurn, Execution, Evaluation, SkillObservation, and PracticeRecommendation.

Exercise versions freeze requirements/assets/rules for an attempt. Evaluation versions preserve which rubric and evaluator produced a result. Evidence references use stable artifact revisions, line locations, event identifiers, and diagram element identifiers.

## Session and runtime contract

Briefing -> Preparing -> Ready -> Active -> Submitted -> Reviewing -> Reviewed. Paused and Recovering states depend on mode and explicit interruption rules.

Server owns assessment time. Start only after readiness checks. Capture latest acknowledged revision at timeout. Display the submitted revision. Define reconnect grace and infrastructure-failure behavior in advance; never silently grade an infrastructure failure as candidate failure.

Run user code outside the platform application server, with resource limits, controlled network access, no platform credentials, and session isolation. An ordinary shared container configuration is not by itself an accepted security boundary; validate the execution platform before untrusted workloads.

Separate private grading/reference assets from the editable workspace. Grade immutable submissions in fresh environments. Protect grading integrity against submitted code influencing the test harness. Checkpoint code and structured diagrams for recovery.

## Review pipeline

1. Collect immutable artifacts, assistance history, transcript, and execution evidence.
2. Evaluate applicable rubric dimensions.
3. Verify executable claims where feasible.
4. Reject unsupported/conflicting findings.
5. Produce actionable feedback and recommendations.

Interviewer context excludes private answers. Treat candidate code, comments, output, and speech as untrusted content rather than evaluator instructions. Calibrate against human-reviewed strong, weak, partial, and alternative submissions.

## Delivery checkpoints

1. Detailed experience design and representative contracts for all tracks.
2. Shared account/session/persistence/voice/review foundation.
3. Reliable Rails/Ruby coding environments.
4. Design canvas and system design interview flow.
5. Curriculum depth, calibrated evaluation, revisions, adaptive practice.
6. End-to-end reliability, isolation, accessibility, and cost validation.

Release acceptance requires substantial sessions in all three tracks, useful evidence-based reviews, revisions, reliable voice/execution, saved history, connection recovery, acceptance of valid alternatives, and measured representative operating costs.
