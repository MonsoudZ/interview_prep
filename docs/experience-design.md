# Screen flows and workspace behavior

Status: proposed design. No UI has been implemented.

## First visit

1. Sign in to the private application. Public registration is disabled initially.
2. Confirm senior backend target, Rails implementation track, and Ruby challenge language.
3. Choose optional weekly practice goals, microphone settings, and recording retention.
4. Start guided practice, choose an exercise, or take an optional diagnostic.

Microphone denial must never block text-based practice. Do not require a diagnostic before access.

## Home and discovery

Home presents resume, one recommended exercise with an evidence-based explanation, and direct entry to all tracks. Empty-state recommendation: guided Rails request-flow lesson, because this matches the user's stated baseline. No invented diagnostic result.

Library filters: track, topic, prerequisite skill, difficulty, format, support level, expected duration, completed/unseen. Duration is guidance, not a universal success threshold.

Learning path presents prerequisites and suggested sequence without locking out topics. Each skill shows evidence, assistance history, and a suggested next independent check.

## Briefing

Show task requirements, starter contents, allowed tools/docs, visible versus private checks, assessment duration, pause/disconnection rules, and recording policy.

Environment preparation is separate from assessment time. Show preparing, ready, or actionable error. The user explicitly starts once ready. Preparation failure offers retry without consuming an attempt.

## Coding workspace

```text
Exercise / mode            Save status     Timer     Mic     Submit
Files          Editor tabs / code                   Brief / conversation
               Terminal / structured test output   Hints when permitted
```

Resizable/collapsible panels; keyboard navigation; adjustable font size; text alternatives for audio; status announcements that do not steal focus. Desktop is the primary editing experience. Smaller screens can browse and review, with an explicit limited-workspace layout.

Editor supports file operations, find/search, syntax highlighting, indentation, diagnostics, and ordinary completion. AI code generation is a separate permission; ordinary completion does not silently enable it.

Show pending, saved, offline, and conflict states. Single active writer per session initially; opening another tab offers read-only access or an explicit takeover. Do not resolve conflicting edits by silently overwriting.

Run one test or suite, inspect output, cancel commands, and use terminal commands within exercise permissions. Stop runaway processes without resetting files. Runtime reset preserves a checkpoint and explains whether database state will reset.

For failed tests, show command, execution status, expected/actual output when available, and relevant file links. Distinguish compilation/setup errors, assertion failures, timeouts, and infrastructure faults.

## System design workspace

Replace editor with a canvas. Palette includes client, service, datastore, queue, cache, external dependency, boundary, connection, and annotation. Elements have stable IDs, labels, descriptions, and editable attributes. Connections have direction and semantics. Provide a keyboard-accessible structured outline alongside the canvas.

Notes tabs: requirements, estimates, API contracts, data model, tradeoffs, failure cases. The interviewer can refer to selected elements and state which diagram revision it is discussing. Freeform drawings are annotations, not silently inferred architectural facts.

## Voice and support

Persistent mic state, interrupt control, transcript, and text input. Stop spoken output when interrupted; keep the conversation consistent. Transcripts may be corrected with original text preserved for audit. Show transcription uncertainty and allow clarification before evaluating ambiguous statements.

Hints expose four levels and record which was used. Assessment requests for help receive a clear rule explanation and an option to convert to practice. Conversion ends independent assessment status while preserving work and history.

## Submission and interruptions

Early submit confirms the acknowledged artifact revision and any unsaved buffer. At timeout, lock assessment writes and capture the latest acknowledged revision. Preserve later-arriving edits as ungraded recovery material; never silently include them in the timed submission.

Proposed default: client disconnection does not pause an assessment. If the deadline passes offline, submit the server checkpoint. A platform execution outage invalidates timed comparability; offer a resumed practice attempt or a fresh assessment. Show this policy before starting. Voice-only failure permits continuing through text; allow the user to mark communication evidence incomplete.

## Review, revision, and history

Review starts with practice verdict, confidence, key strengths, and top fixes. Tabs expose artifact annotations, executions, transcript/timeline, rubric, and reference alternatives. Incomplete analysis is labeled; partial results never masquerade as a completed review.

Create revision from the immutable submission. Re-run relevant checks and compare findings resolved, remaining, or newly introduced. Independent assessment and assisted revision remain separate observations.

History filters by track, skill, mode, and date. Reopen artifacts or start a fresh attempt. Export code/diagram, transcript, and review with private solution material excluded unless already intentionally revealed.

## Settings

Profile, documentation/assistance presets, voice preferences, optional audio recording, retention, usage, exports, and deletion. Deletion removes artifacts and derived personal skill observations, subject to a documented backup expiration policy. Cost and destructive actions must have clear confirmation states.
