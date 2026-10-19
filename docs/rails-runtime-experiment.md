# Rails runtime experiment results

Date: 2026-10-16. Scope: trusted local preparation, execution, source recovery, and process lifecycle. See [experiment README](../experiments/rails-runtime/README.md) for rerun instructions and limitations, and [raw output](../experiments/rails-runtime/results/latest.json) for full measured evidence.

## Observed results

| Check | Result |
| --- | --- |
| Minimal Rails project readiness | Passed; 0.739 seconds including source copy, using preinstalled gems |
| Starter | 12 runs, 12 failures, no errors/skips |
| Reference | 12 runs, 158 assertions, no failures/errors/skips |
| Deliberate create-status regression | 7 failures detected |
| Restore to fresh directory/process and rebuild database | 12 runs, 158 assertions, no failures/errors/skips |
| Source revision match after recovery | Passed |
| Changed checkpoint source | Restore rejected |
| Process exceeding deadline | Process group killed; timeout reported |

These results are one local measurement, not a statistical performance benchmark. The raw report is replaced on rerun, so measured durations can change.

The exercise intentionally provides schema and routes. It validates the runtime pipeline and representative API behavior; it is not yet the full minimal-repository senior assessment or the developed curriculum.

## Decision

Real Rails API tests and source recovery are feasible with the available local stack. Proceed next to hosted runtime provider evaluation and isolation experiments before exposing code execution to uploaded or AI-generated submissions. Nothing has been deployed or provisioned.

Local recovery excludes database contents. Secure execution, hosted cold starts, browser synchronization, final grading integrity, network behavior, and operating costs remain unverified.

The next research step is complete: see the [hosted runtime comparison and live experiment plan](hosted-runtime-evaluation.md). It recommends testing Modal first, pending account access and an agreed trial budget; no hosted benchmark has run.
