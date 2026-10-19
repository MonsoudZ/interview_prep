# Railway execution adapter

Private Node.js worker using Railway's official `railway` SDK, pinned to 3.16.0 with a dependency lock. It consumes the existing Rails queue and signed job contract. It does not expose a public code-execution endpoint or run candidate code on the application server or this Mac.

## Status

Implemented and tested locally with a fake Railway VM transport: signature/source validation, exact checkpoint selection, create/probe/stage/execute/destroy lifecycle, bounded output/deadlines, persistent replay protection, callback retry, cleanup reconciliation, readiness, and a conservative per-worker daily run limit. Ruby-issued signatures are verified by the real Node contract in Rails integration tests.

**Actual Railway VM execution is unverified.** The bootstrap, namespace support, Ruby package compatibility, resource enforcement, teardown, and latency must pass the opt-in live test. The worker refuses candidate execution when its trusted isolation probe fails. No infrastructure was provisioned or checkpoint built during local implementation.

Railway CLI 4.35.0 installed on the development Mac does not have `sandbox`; the adapter uses the SDK directly and does not require a global CLI upgrade. The initially linked unrelated project, `Focusmate-API`, was not modified. The user subsequently selected a separate [Interview Studio project](../../deploy/railway/README.md), which was created and linked. Credentials/environment selection for the adapter remain explicit rather than inherited from the CLI link. No compute services or sandboxes have been provisioned.

## Install and inspect without creating resources

From this directory, using Node 22 or later:

```sh
npm ci --ignore-scripts --no-audit --no-fund
npm test
node cli.mjs plan
node cli.mjs doctor
```

`plan` and `doctor` are local-only and never contact Railway. `doctor` exits 2 if disabled or missing configuration. `check` performs a read-only lookup for the exact expected checkpoint, using configured credentials. None of these commands builds or creates a VM.

## Configuration

Use [the environment template](../../deploy/railway-worker/environment.example) via secure process/Railway Variables configuration. It is not automatically loaded. Do not paste real keys into source, URLs, commands, or chat.

| Variable | Purpose |
| --- | --- |
| `RAILWAY_API_TOKEN` | Railway account/workspace API token used by the trusted controller; explicit bearer authentication |
| `RAILWAY_ENVIRONMENT_ID` | Explicitly chosen interview environment UUID; do not reuse an unrelated app's environment |
| `INTERVIEW_WORKER_ID` | Stable random worker UUID |
| `INTERVIEW_CONTROL_PLANE_URL` | Rails origin; HTTPS except loopback development |
| `INTERVIEW_WORKER_BRIDGE_KEY` | At least 32 bytes; matches the Rails bridge key |
| `INTERVIEW_WORKER_SIGNING_KEY` | At least 32 bytes; matches the Rails signing key |
| `INTERVIEW_RAILWAY_EXECUTION_ENABLED` | `1` enables commands that can create billable VMs; default disabled |
| `INTERVIEW_RAILWAY_DAILY_JOB_LIMIT` | 1–100 runs per worker per UTC day; default 10; preparation and manual signed runs count |
| `INTERVIEW_WORKER_STATE` | Private persistent directory; default worker `.state` |

The controller passes no provider, signing, bridge, database, or app secrets to the VM. It creates a sandbox with an empty environment map, no public domains, `ISOLATED` networking, a one-minute idle timeout, and explicit 1 vCPU/2 GB resource ceilings.

## Build the reusable Rails checkpoint

Do this only after selecting the interview project/environment and establishing available Railway allowance. **Bootstrap and execution consume Railway usage.** Enabling the variable is not proof that a run will fit in the included allowance.

```sh
node cli.mjs bootstrap
node cli.mjs check
```

Bootstrap uploads a fixed allowlist of trusted starter/test/runner assets, installs Ruby >=3.2 from the sandbox's Ubuntu apt repositories, installs Bundler 4.0.3 and frozen generic-Ruby locked gems, creates a non-root account, checks isolation and Rails preparation, empties the writable workspace, captures a checkpoint, and destroys the build VM. It never includes the reference solution.

Checkpoint names include a hash of the trusted assets, lock, scripts, and probe. Changing these inputs requires a new checkpoint. This pins exercise content/dependencies; it does not pin the vendor Ubuntu image or apt package versions. Record actual Ruby, OS, and build provenance during live validation before treating this as a production runtime.

## Run against Rails

Configure the two matching worker keys in Rails, then start the application normally. With the checkpoint ready:

```sh
node cli.mjs bridge
```

For a single lease-poll cycle:

```sh
node cli.mjs bridge --once
```

The bridge first verifies the exact checkpoint exists. It reconciles expired owned runtimes, retries persisted callbacks, checks its daily job limit, advertises heartbeat/capabilities, and leases one job. It verifies the short-lived HMAC and source revision before creating a VM. Results return with the original lease and revision, and include `runtime_provider: railway_sandbox`.

Each run starts from the clean checkpoint. A trusted probe runs before any candidate files are uploaded. Candidate execution uses a new network/PID/mount namespace, a non-root UID (20000), dropped capabilities, no-new-privileges, a private tmpfs, and process/file/address-space limits. The network namespace has no configured route; the probe checks interfaces and a blocked external TCP connection. Railway's `ISOLATED` mode alone still permits outbound internet and is not used as a substitute for this check.

The controller bounds creation/staging/exec/cleanup calls; the SDK command and a trusted `timeout` inside the VM bound execution. Output is limited to 256 KiB. Termination, failed execution, timeout, output limit, and infrastructure failures remain distinct; no pass result is fabricated on interruption.

## Recovery and budgets

Persist the state directory on a private volume writable by the worker UID. Receipt files are mode 0600 and contain job identity, sandbox IDs, lease tokens, and results; source contents are not retained in receipts. Keep one worker instance initially. Local receipts and the daily limit are per worker/state directory, not a fleet-wide budget or an exact dollar cap. Do not erase receipts to reset limits or bypass replay checks.

```sh
node cli.mjs reap
```

Schedule reconciliation independently at least once a minute using the same environment and state volume. It connects to and destroys only recorded expired/cleanup-pending sandboxes in the configured environment. It never lists/deletes other project workloads. Interrupted jobs become infrastructure failures and require an explicit new run; callbacks retry without re-executing code. Rejected 404/409 deliveries remain recorded. Cleanup failures stop new allocation until resolved. The one-minute provider idle timeout is additional protection for an unconfirmed create; it is not a substitute for cleanup, since active commands defer idle teardown.

Railway VM usage draws from the plan's existing allowance. Application/database usage also consumes that allowance. The daily count limit, resource ceilings, short deadlines, and cleanup reduce waste but cannot guarantee an unchanged bill. Workspace-wide spending limits affect other workloads and are not changed by this integration.

## Live verification

After bootstrap and budget/configuration checks, from `apps/platform`:

```sh
RUN_RAILWAY_WORKER_INTEGRATION=1 ruby bin/rails test test/integration/live_railway_worker_test.rb
```

This deliberately creates **three real sandboxes**: Rails preparation, 12 failing starter tests, and the reference passing 12 tests/158 assertions. It exercises the real Rails account/session/queue/lease/signing/callback path, real SDK execution and runtime probe, reported test counts, revision matching, and immutable submission. It calls the direct signed-job `run` command, so it does not validate a hosted HTTP deployment or the long-running networked bridge/browser end to end. Default test runs skip it.

The Dockerfile at `deploy/railway-worker/Dockerfile` is prepared for a separate worker service with repository-root build context. It has not been built here. Configure the state-volume ownership for UID 1000 and secure control-plane routing before deployment. Do not deploy this worker to the existing unrelated CLI-linked project.

## Grading limits

Visible tests run inside the candidate process trust boundary. Output/counts are execution evidence and can be influenced by candidate code; the UI explicitly calls them runner-reported. They are not a tamper-proof assessment verdict or calibrated AI review. Independent black-box grading and adversarial isolation testing remain release gates.

## Official references

Checked 2026-10-16: [Railway Sandboxes](https://docs.railway.com/sandboxes), [official SDK source](https://github.com/railwayapp/railway-ts-sdk), [VM billing and included allowance](https://docs.railway.com/pricing/plans), [cost controls](https://docs.railway.com/pricing/cost-control).
