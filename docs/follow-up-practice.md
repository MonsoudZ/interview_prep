# Follow-up interview practice

Implemented 2026-10-18. Open a submitted Rails, Ruby, or system-design attempt's review and choose **Practice follow-up questions**. The same action is available in its Support panel. Recent rounds can be resumed from Progress.

## Question flow

Questions are scripted from the exercise's published senior rubric probes, followed by a changed-requirement extension. They are rehearsal prompts with prior exposure, not a claim of an unseen interview or adaptive AI interviewer. The complete question set, review focuses, practice suggestions, rubric version, and source snapshot identity are captured when the round is prepared.

Choose guided or timed mode before **Start follow-up round**. Guided mode has no deadline. Timed mode allocates two minutes per question for the whole round: a six-question round has a twelve-minute budget, while a seven-question round has fourteen minutes. Preparing a round does not start its clock. Closing the window or disconnecting does not pause a timed round.

One question is shown at a time. Answers autosave, with an 8,000-character limit per answer. Next requires a nonblank response and locks it before advancing. Skip records an explicit skip and preserves any partial text. Finishing early preserves the current text as partial and leaves future questions unasked. Guidance appears after completion, not in the active round payload. At a deadline, the server preserves only the last saved draft, marks it partial, and rejects later writes. Completed answers have no edit command.

## Resume and conflict handling

There is at most one unfinished round per source submission and two per account. An unfinished round is resumed rather than duplicated. Creation uses a UUID request identity; repeated requests for a created round return that round, including after completion.

All edits use a saved version and question index. A stale tab cannot advance or replace another tab's answer. The browser keeps unsaved text when a conflict occurs and offers an explicit reload/discard action. If a deadline ends the round while local text is unsaved, that text is shown separately and can be exported, without being added to the accepted transcript. Close attempts save first; explicit discard remains available. Browser unload protection covers unsaved answers and self-checks.

Deep links use `/#session/<source-id>/followup/<round-id>` and restore the saved round after refresh. Closing the round returns the hash to its source session. Progress lists the ten most recently updated rounds across tracks, with filtered resume/view actions. The direct round loader also checks that the round belongs to the displayed source submission.

## Review and export

Completed rounds show every prompt, saved response, and its actual state: answered, skipped, partial, or unanswered. Published review focuses are reflection aids, not an answer key or automated judgment. Self-checks use Not reviewed, Needs practice, or Explained in my answer. Observed self-checks need a reason, and skipped/partial/unanswered responses cannot be marked explained. Self-check edits use the same optimistic version protection and do not alter the answers.

The round's reflection and self-reported practice gaps are saved separately from coding/design reviews and starter-attempt progress. No aggregate mastery or hiring score is calculated. Transcript download is plain text with source/rubric provenance, timing, response states, saved self-checks, and reflection. Unsaved local text, if included, is labeled outside the saved round.

No model, voice service, camera, or paid provider is invoked. Existing code/design model packets explicitly exclude follow-up transcripts; a completed typed round does not retroactively change an earlier model report.

## Access and validation

GET/POST `/api/sessions/:id/followups` lists or prepares rounds for an owned submitted session. GET/PATCH `/api/followups/:id` reads or commands an owned round. Commands are start, save, next, skip, finish, and review. Answer content and self-check fields are filtered from request logs. The local application was restarted to apply the updated filters.

Nine new Rails integration tests add 168 assertions covering all tracks, preparation, hidden guidance, versioned saves, quotas, idempotency, skips, partials, immutable responses, deadline completion despite rejected late writes, self-check validation, progress isolation, and ownership. Five frontend tests cover draft reconciliation, competing reviews, late local text, escaping, and transcript export.

Browser verification used a clearly labeled fixture on the existing synthetic design submission. It covered timed start, answer save/close/resume, deep-link reload, next, skip, early finish, self-check validation, transcript download, Progress navigation, and app restart persistence. All personal performance ratings were left Not reviewed. A 390-pixel mobile layout was checked without page overflow and the temporary viewport override was reset. Screenshots and the downloaded example are in `artifacts/` and excluded from the Studio code package.
