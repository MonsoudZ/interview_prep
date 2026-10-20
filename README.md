# Interview Prep

A working interview preparation application for senior Rails/backend roles, with practical repository exercises, Ruby challenges, and system design practice.

Clone the source with `git clone https://github.com/MonsoudZ/interview_prep.git`. For a new Mac Studio installation, follow the [Studio setup guide](deploy/studio/README.md). Git contains application code and curriculum; accounts, practice history, local worker credentials, and exported artifacts stay on each machine. Transfer existing practice history using the guide's private database backup procedure.

## Design documents

- [Product specification](docs/product-specification.md)
- [Exercise and evaluation contracts](docs/exercise-contracts.md)
- [Screen flows and workspace behavior](docs/experience-design.md)
- [Technical design and decision register](docs/technical-design.md)
- [Curriculum and evaluation framework](docs/curriculum-and-evaluation.md)
- [Delivery roadmap and release acceptance](docs/delivery-plan.md)
- [Hosted runtime comparison and experiment plan](docs/hosted-runtime-evaluation.md)
- [Self-hosted platform architecture decision](docs/decisions/001-self-hosted-platform.md)
- [Railway-only hosting and existing-budget constraint](docs/decisions/002-railway-only-budget.md)
- [Railway sandbox worker setup and verification](services/railway_worker/README.md)
- [Separate Interview Studio Railway project](deploy/railway/README.md)
- [Execution worker implementation and verification](services/execution_worker/README.md)
- [Rails application and browser workspace](apps/platform/README.md)
- [Linux development worker setup and live validation](deploy/linux-worker/README.md)
- [Local Linux VM: running setup and start/stop commands](deploy/local-vm/README.md)
- [Central Mac Studio setup, local-model reviews, and laptop access](deploy/studio/README.md)
- [Progress tracking and focused practice](docs/progress-tracking.md)
- [Revision practice and saved source comparisons](docs/revision-practice.md)
- [Follow-up interview rounds and transcripts](docs/follow-up-practice.md)
- [Complete mock interviews and consolidated reviews](docs/mock-interviews.md)
- [Session organization, archiving and restore](docs/session-management.md)

The product includes practical Rails assessments, Ruby coding challenges, and system design interviews. The planned full product includes learning, independent practice, voice/text interviews, evidence-based reviews, and revisions. Current implemented behavior is described below.

The [Rails application foundation](apps/platform/README.md) now includes accounts, versioned exercises, saved browser workspaces, server-timed sessions, immutable submissions, and a durable execution queue/worker bridge. All eighteen current exercises have progressive guided hints and saved submission self-reviews with senior-level criteria, source references, reflections, and gap-based practice suggestions. The [local Linux VM](deploy/local-vm/README.md) now runs the self-hosted Docker/gVisor worker: the real queue/signature/execution/callback test passes, and the browser displays actual starter failures and reference success. The [published curriculum](curriculum/README.md) now includes eight executable Rails repositories (96 test groups) and executable Ruby intervals with visible, supplemental, and 100,000-input checks. Submitted Rails/Ruby attempts can reveal tested reference files. System design version 2 adds an architecture canvas, six notes sections, SVG/JSON/Markdown export, and source-bound submission review. Live model validation, voice, and further curriculum expansion remain outstanding. The separate Railway project exists; no hosted compute has been deployed.

Planning documents describe the intended complete release. The platform should grow beyond personal use, with Railway as the only hosting provider and no additional paid services. The [Railway Sandboxes adapter](services/railway_worker/README.md) is implemented with local simulated-provider tests; actual hosted execution remains unverified pending interview-project configuration, credentials, and available-allowance validation. The workspace now includes a locally bundled code editor, adjustable/restored panels, automatic draft preparation, exercise task/level/tool previews, and revision-bound failure diagnostics with raw runner output. The dedicated Linux worker is optional, not a requirement to buy another host. See [the current hosting decision](docs/decisions/002-railway-only-budget.md). Further exercise expansion, reviewer calibration, and deployment remain future work.

Local-model review integration now supports a private Ollama worker, explicit review requests, frozen evidence packets, validated source citations, rubric observations, and model/version provenance. Self-assessment remains independent. The Studio transfer tools create code-only archives and consistent private database backups. This integration was tested with synthetic model responses; installing and benchmarking an actual model on the Mac Studio remains outstanding. See the [Studio setup guide](deploy/studio/README.md) and [verification](deploy/studio/VERIFICATION.md).

The Progress page now turns saved self-assessments into a focused practice plan, tracks repeated criterion gaps and rating history within each rubric version, and queues unfinished reviews. Focused attempts carry their drill into the workspace. Reported runner results stay separate from ratings. See [progress tracking](docs/progress-tracking.md) for the comparison rules and verification.

Submitted attempts can now be reworked in a separate guided or timed workspace with captured feedback, saved source comparisons, design before/after previews, and an independent submission/review. Rework ratings stay separate from starter-attempt progress. See [revision practice](docs/revision-practice.md).

Submitted attempts also support scripted senior follow-up rounds, guided or timed, with autosaved typed answers, resume links, explicit skips/partials, separate self-checks, and plain-text transcript export. The questions use the published exercise rubric and do not invoke a model or voice service. See [follow-up practice](docs/follow-up-practice.md).

Current development path: [ADR 003 — local Linux VM](docs/decisions/003-local-linux-development.md). Start `colima start interview`, then `python3 services/local_vm/dev.py start`, and open [the studio](http://127.0.0.1:3100/). The VM runs on this Mac; it does not consume Railway sandbox usage.

Mock interviews now combine pinned Rails/Ruby/design exercises and cross-exercise follow-ups in one saved timed workflow, with server-enforced stage and overall deadlines, resume links, early finish, revision-bound evidence, focused practice suggestions, an overall reflection and review export. Three schedules cover debugging, migration and a full senior backend loop. See [the interview guide](docs/mock-interviews.md).

Behavioral practice adds five senior question sets, a versioned story bank, guided or timed typed rehearsal, answer-only review evidence and a 54-minute full interview. See [behavioral practice](docs/behavioral-interviews.md).
