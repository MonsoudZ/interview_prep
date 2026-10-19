# Session organization and cleanup

Sessions, exercises, mock interviews, reworks and follow-up rounds retain their separate meanings. An exercise is a published task; a session is an attempt; a rework is a new attempt linked to a submission; a mock interview owns an ordered set of timed stages; a follow-up round preserves typed answers about submitted work.

## Find saved work

Sessions has All, In progress, Submitted and Archived views, plus search and practice-type filters for Rails, Ruby, system design, reworks and interview stages. Search/filter applies to the loaded list, currently the latest 100 sessions in the selected archive scope; the interface shows the loaded and total counts. Dashboard totals count all unarchived sessions rather than treating the limited list as complete history. Submitted dates remain stable when an item is archived or restored.

Sessions (`#sessions`), Exercises (`#exercises`) and Progress (`#progress`) survive a page reload. Interview stages link directly to their owning interview. Workspace back navigation returns interview stages to their schedule/review and standalone work to its originating dashboard page.

Session and Progress endpoints reconcile elapsed stage/overall timers before reporting status. An expired timed attempt cannot remain listed as active merely because its editor was not reopened. Prepared timed sessions disable Start while their required worker is offline; guided writing remains available.

## Archive and restore

Archive is reversible organization, not deletion or an assessment state. There is no permanent-delete flow.

- Completed standalone sessions have Archive/Restore controls in Sessions. Active, unstarted and preparing work must be completed before archiving; archiving cannot pause a timer.
- Finish any unfinished follow-up round before archiving its source. Archived sources cannot launch new follow-up rounds until restored. Existing reviews and completed transcripts remain readable.
- Complete mock interviews archive/restore together with every created source stage. Individual stage archive/restore is rejected, preventing a partially hidden interview. Open the owning Interview to restore the group.
- Archived records disappear from normal session/interview lists, recent Progress attempts, the review queue and recent follow-up list. Existing criterion ratings and accumulated progress remain; archiving does not manufacture improvement or erase evidence.
- Original submissions, snapshot contents, executions, references, review entries, transcripts and overall reflections are retained. Archive/restore endpoints use the signed-in account's ownership scope. No archived data is published to Git.

The local verification interview with an explicit synthetic-fixture reflection was archived through the application, restored to verify the round trip, then archived again. Other practice sessions were preserved. This is not a reset of the user's account or performance history.

## Presentation fixes

Rails curriculum sessions open their relevant controller/job/backfill instead of defaulting to the shared Events stub. Published exercise versions and existing snapshots are unchanged. Design workspaces describe their current architecture/notes/review tools rather than promising already-built features. A read-only empty diagram no longer instructs the user to add disabled components. Mock stage instructions distinguish work before Start from a submitted read-only stage. Mobile session rows show complete titles above status/actions instead of squeezing the title and date between buttons.

## Verification

Seven integration tests cover archive idempotency, restore, unchanged snapshots/reviews, retained progress, hiding archived review tasks, active-state guards, unfinished follow-up guards, mock group consistency, overdue list reconciliation, owner isolation and relevant Rails entry files. Frontend tests cover combined filters, safe text rendering, archive eligibility, reload hashes, design copy and offline Start behavior.

Latest checks: **112 Rails runs, 1,399 assertions, no failures/errors, four expected opt-in skips; 48 frontend tests passed; formatting, diff whitespace and eager loading passed.** Browser verification covered search focus, normal and archived lists, parent navigation, interview restore/rearchive, reloads and a 390px layout with no horizontal document overflow. Execution isolation and curriculum files did not change in this cleanup; the earlier real sandbox verification remains applicable.
