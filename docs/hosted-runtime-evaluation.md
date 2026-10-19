# Hosted runtime evaluation

Researched 2026-10-16 using official documentation. This is a documentation-based shortlist, not a hosted benchmark, penetration test, or provider certification. No cloud resources were created.

**Superseded primary direction:** the user subsequently chose a self-hosted execution service designed for growth. See [ADR 001](decisions/001-self-hosted-platform.md). Preserve this comparison as fallback research; a Modal account is no longer a development prerequisite.

## Recommendation

Test **Modal Sandboxes first**, with E2B as the alternative. Modal's documented runtime duration and network controls suit longer practice sessions without building the initial design around a one-hour runtime ceiling. This is an engineering inference from documented capabilities, conditional on the hosted experiment below.

Use a provider adapter: prepare, readiness, file read/write, execute/cancel, terminal attach/resize/disconnect, checkpoint/restore, inspect usage, and terminate. Keep canonical code snapshots in application-owned storage so changing providers remains feasible.

Do not select ordinary shared containers on the application host. Specify a runtime boundary explicitly and validate it. Provider documentation is evidence of advertised controls, not evidence that our integration configures them correctly.

## Comparison

| Requirement | Modal | E2B | Daytona |
| --- | --- | --- | --- |
| Execution boundary | Documents gVisor and VM choices [M1] | Documents isolated Linux VMs [E1] | Documents separate container and VM classes; choose intentionally [D1] |
| Rails setup | Custom images; Rails compatibility must be measured [M1] | Prepare a Ruby-capable environment; not yet tested | Snapshots/custom environment; Rails compatibility not yet tested |
| Interactive terminal | PTY option documented in SDK [M2] | Dedicated PTY API [E2] | Dedicated PTY API, including Ruby examples [D2] |
| Persistence | Filesystem snapshots and filesystem API [M2, M3] | Pause/resume persistence [E3] | Filesystem survives stop/start; VM memory persistence differs from containers [D3] |
| Outbound denial | Explicit block_network control [M4] | Explicit internet disable/deny controls [E4] | Configurable sandbox firewall requires eligible tier; not a baseline assumption [D4] |
| Session duration | Up to 24 hours; default must be overridden [M1] | Hobby 1 hour; Pro 24 hours [E1] | Validate selected class, lifecycle, and account limits before use |
| Primary concern | Integration quality, sizing, cost under actual consumption | One-hour Hobby limit; paid plan for longer continuous sessions | Tier eligibility and selected isolation class |

No candidate has yet passed a remote Rails test run. Startup slogans are not measurements; none are used to claim an application readiness time.

## Compute-only cost model

Normalize to **2 vCPU-equivalent and 4 GiB** for a first comparison. Modal bills physical CPU cores, documented as two vCPUs per core. Equal labels do not guarantee equal performance. All prices USD, checked on the research date.

| Provider | Listed inputs | Calculated compute/hour |
| --- | --- | --- |
| Modal Sandboxes | 1 physical core at $0.00003942/second + 4 GiB at $0.00000667/GiB/second [M5] | $0.23796 |
| E2B | 2 vCPUs at $0.000014/vCPU/second + 4 GiB at $0.0000045/GiB/second [E5] | $0.16560 |
| Daytona | 2 vCPUs at $0.0504/vCPU/hour + 4 GiB at $0.0162/GiB/hour [D5] | $0.16560 base-rate illustration |

Modal bills the higher of reserved and actual usage; configure resource ceilings and confirm allocation semantics rather than treating this estimate as a hard cap [M6]. Daytona figure is not a quote for a particular VM class/tier; eligibility or class pricing must be confirmed. All figures exclude storage, snapshots, builds, retained idle state, grading workers, AI, voice, app hosting, taxes, and any required plan charges.

Example: 20 hours of practice plus 10 hours of setup/grading overhead is 30 billed compute hours. Arithmetic: Modal about $7.14; E2B or Daytona listed base compute about $4.97. This is an assumed workload, not observed monthly usage. A separate grading sandbox adds billed time.

E2B lists a $150/month Pro base charge plus usage; do not omit that when continuous sessions require Pro [E5]. Credits and account eligibility are excluded from estimates. Recheck rates before a paid run.

## Hosted experiment specification

### Inputs and limits

- Trusted Rails template/reference from the completed local experiment.
- Explicit runtime choice, region, resource request/limits, and image/dependency versions.
- Initial proposed resource limit: 1 physical CPU-equivalent core and 4 GiB RAM. Tune down after measurement.
- At most two simultaneous sandboxes: candidate and recovery/checking instance.
- Ten-minute lifetime per sandbox, explicit cleanup in success/failure paths, and a follow-up check for leaked resources.
- Propose a $5 total trial budget for builds, runtime, and storage, subject to user agreement. This is a spending target, not a provider-enforced guarantee. Confirm quotas/credits and build-cost exposure before launch.
- No platform secrets or cloud credentials injected into the candidate environment.

### Image preparation

Prepare a Linux Ruby image with pinned Rails/SQLite dependencies. The existing local lockfile includes macOS artifacts; generate and retain an appropriate Linux lockfile rather than assuming it is portable. Bake dependencies into the image, and block runtime egress after readiness. Record image identity and lockfile checksum.

Do not combine dependency downloads with candidate assessment time. Keep reference solution assets out of the starter image; upload them only during this trusted validation sequence.

### Sequence and required evidence

1. Build image; record build time/cost separately from readiness.
2. Create sandbox with explicit limits and blocked outbound networking; record request-to-process-ready timing.
3. Copy starter and prepare DB; record application-ready timing. Never equate an allocated sandbox with a ready Rails app.
4. Execute the 12 tests; expect 12 assertion failures and zero setup errors.
5. Apply reference through the same file interface intended for editor saves. Run tests; expect 12 passing tests and 158 assertions for the current suite.
6. Attach PTY, resize it, edit a file through shell input, and read the change through the filesystem API.
7. Introduce the known status regression; confirm failures and authoritative process exit status.
8. Save a verified source checkpoint outside the candidate runtime. Restore a fresh sandbox, rebuild DB, and expect 12/12 passing.
9. Separately test provider filesystem persistence with a benign marker file and SQLite row. Record whether processes, disk, and DB state survive each lifecycle operation; do not conflate them.
10. Check outbound policy at the application protocol level, not merely TCP connect success. Test IPv4/IPv6 and available routes; unsupported cases remain explicit.
11. Demonstrate cancellation and lifetime expiry; verify no surviving billed sandbox.
12. Inspect usage and report actual cost, limitations, and any account-level constraints.

For first feasibility, one successful run is enough to identify obvious blockers. A later benchmark should use at least 10 fresh creations and 10 resumes, recording distribution and sample count rather than claiming p95 from one attempt. Proposed performance targets remain provisional until measurement.

### Pass conditions

Actual Rails tests execute correctly; filesystem and PTY operate on the same project; external source recovery works; configured network policy is verified for tested protocols; termination is reliable; usage is attributable; account costs and longer-session constraints are understood.

A clean result is not a proof of sandbox security. Complete broader adversarial isolation/resource testing before accepting arbitrary uploaded code.

## Current access status

Local checks found no installed Modal SDK, no configured Modal environment authentication, and no default Modal configuration file. No credential contents were read or printed. A live experiment therefore needs an authenticated account and agreed trial budget. Do not ask for secrets in chat; configure credentials through the provider's supported local login or secure environment mechanism after checking current official setup instructions.

Provider selection remains provisional until the live test completes. Browser editor/terminal integration and AI/voice experiments can proceed independently once authorized.

## Official sources

- [M1: Modal sandbox lifecycle and runtimes](https://modal.com/docs/guide/sandboxes)
- [M2: Modal Sandbox SDK, PTY and snapshots](https://modal.com/docs/sdk/js/latest/Sandbox)
- [M3: Modal filesystem access](https://modal.com/docs/guide/sandbox-files)
- [M4: Modal networking and security](https://modal.com/docs/guide/sandbox-networking)
- [M5: Modal pricing — Sandbox section](https://modal.com/pricing)
- [M6: Modal sandbox resources and billing](https://modal.com/docs/guide/sandbox-resources)
- [E1: E2B lifecycle and limits](https://docs.e2b.dev/sandbox)
- [E2: E2B interactive terminal](https://docs.e2b.dev/sandbox/pty)
- [E3: E2B persistence](https://docs.e2b.dev/sandbox/persistence)
- [E4: E2B internet access](https://docs.e2b.dev/network/internet-access)
- [E5: E2B pricing](https://e2b.dev/pricing)
- [D1: Daytona isolation classes](https://www.daytona.io/docs/en/isolation/)
- [D2: Daytona PTY](https://www.daytona.io/docs/en/pty/)
- [D3: Daytona persistence](https://www.daytona.io/docs/en/persistence/)
- [D4: Daytona network controls and tier restrictions](https://www.daytona.io/docs/en/network-limits/)
- [D5: Daytona pricing](https://www.daytona.io/pricing)
