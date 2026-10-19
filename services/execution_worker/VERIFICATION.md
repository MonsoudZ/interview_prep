# Verification record

## Current local VM milestone — 2026-10-17

The image was built and real Docker/gVisor execution is now verified inside the dedicated Colima VM. The opt-in Rails integration test passed with **1 run, 39 assertions, zero failures/errors/skips**, including actual preparation, 12 starter failures, reference success (12 tests/158 assertions), identity/revision callbacks, immutable submission, non-root UID, absent Docker socket, rejected image-path writes, and blocked outbound IPv4 TCP. The browser/long-running local bridge also displayed actual starter and reference results. An independent cron reaper removed an expired worker-owned test container. See [detailed verification](../../deploy/local-vm/VERIFICATION.md) and [runtime provenance](../../deploy/local-vm/runtime.json).

## Historical preparation milestones

Date: 2026-10-16. Host: macOS, Python 3.9.6, Ruby 4.0.1, Rails 8.1.4.

Linux deployment preparation milestone: **27 worker/deployment/bridge checks pass** in 14.840 seconds. Added a Linux-compatible frozen dependency lock with fetched RubyGems checksums; image/daemon validation; pinned builder; readiness doctor; service/watchdog templates; and an opt-in real execution test. The Rails run reports **23 passing application tests (122 assertions), plus one explicitly skipped live-Linux test**. Doctor reports `ready: false` on this Mac because Docker is absent. The build planner reports `executed: false`; no image was built. About 10 GiB of free disk was observed, so a local VM was deferred in favor of recommending a dedicated Linux development host.

Subsequent application integration milestone: **22 worker/bridge checks pass** (16.335 seconds), including preparation without passing candidate tests and bridge URL/redirect restrictions. The [application verification](../../apps/platform/VERIFICATION.md) records an additional 23 Rails integration tests with 122 assertions. Live Docker/gVisor execution is still unverified.

Original worker-only baseline: `python3 -m unittest discover -s services/execution_worker/tests -v`: **17 tests passed** in 13.838 seconds.

- Two integration checks stage a read-only template into a writable temporary workspace and execute real Rails: starter has 12 failures; reference has 12 passing tests and 158 assertions.
- Fifteen checks cover job authentication, integrity, expiry, path/size restrictions, replay receipts, container command policy, missing-runtime rejection, process timeout/output handling, cleanup failure, and watchdog ownership/expiry.
- Docker orchestration checks use a local fake executable or mocks. They are not evidence of container isolation or a successful image build.
- Generated a reference job and ran command planning: `executed: false`, with mandatory `runsc`, no networking, no mounts, non-root user, and bounded resources in the command.
- Ruby entrypoint syntax, Python syntax, and local documentation links checked successfully.

At the original baseline, no Docker/gVisor image had been built or launched. The local VM milestone above supersedes that limitation. No public execution endpoint or hosted compute has been deployed.
