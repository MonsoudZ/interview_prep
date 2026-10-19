# Self-hosted execution worker

First implementation of the private execution boundary for a growing interview-preparation application. It is not a complete interview app, a public HTTP service, a distributed scheduler, or a validated production sandbox.

Update 2026-10-17: the worker now executes inside the [local Colima Linux VM](../../deploy/local-vm/README.md). The image was built, the real Rails queue/lease/signature/VM execution/callback test passed (39 assertions), observable isolation checks passed, the independent cleanup scheduler removed an expired test container, and browser runs produced real test results. Production/adversarial validation remains separate.

The worker accepts signed, expiring, versioned jobs containing tenant/session identity and a hash-verified source revision. It runs only installed exercise operations using an operator-selected immutable image ID. Jobs cannot supply Docker flags, host paths, network policy, images, or shell commands.

## Implemented

- Version 1 source/job validation, UUID identities, size/path limits, expiry, HMAC verification.
- Durable host-local duplicate-job rejection and execution receipts.
- Mandatory `runsc` runtime; no ordinary Docker or local Ruby fallback.
- Non-root, read-only-root container policy with no networking, host mounts, published ports, inherited application credentials, or extra capabilities.
- CPU/memory/process/tmpfs/file limits; wall-clock and captured-output limits.
- Execution result bound to exact source revision; infrastructure failures separated from ordinary nonzero execution.
- Cleanup verification plus a separate expired-container watchdog command.
- Starter/reference job generation and a trusted Rails image entrypoint.

The current local image installs five Rails scenarios and Ruby intervals, each with an approved test/preparation operation. Rails paths accept only permitted app Ruby files/routes/schema; Ruby accepts only solution.rb. Image inventory controls advertised capabilities. See the [published curriculum](../../curriculum/README.md). Design sessions do not need a code sandbox. The [Rails application](../../apps/platform/README.md) implements durable queue/lease/result endpoints. `bridge.py` polls from a Linux host; `services/local_vm/bridge.py` provides the Mac-to-Linux SSH adapter used by the validated local setup.

## Local checks

```sh
python3 -m unittest discover -s services/execution_worker/tests -v
```

Tests cover signature/source tampering, path restrictions, request policy, replay protection, hardening flags, mandatory runtime, watchdog ownership, output limits, timeout handling, and cleanup failures. Process tests use local fake Docker executables. They do not execute containers or validate gVisor.

Local regression evidence: [27 passing checks, including staging/preparation, deployment policy, and bridge transport](VERIFICATION.md). Ordinary runs still skip the opt-in Linux test; it was separately enabled through the configured VM and passed with 39 assertions. The [VM verification](../../deploy/local-vm/VERIFICATION.md) distinguishes those actual observations from mocked orchestration checks.

Generate a command plan without executing code or needing a secret:

```sh
python3 services/execution_worker/make_example.py --reference > /private/tmp/interview-example.json
python3 services/execution_worker/worker.py plan --image "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" < /private/tmp/interview-example.json
```

The example ID is deliberately illustrative, not a valid installed image. Jobs expire after five minutes; regenerate examples before use. `plan` explicitly does not verify signatures and cannot execute.

## Linux integration procedure

The [local VM variant](../../deploy/local-vm/README.md) has now been executed successfully. The dedicated systemd deployment below remains a recipe for a future standalone host.

1. Use a dedicated Linux execution host, separate from the application and its database. Install Docker and gVisor/runsc using official instructions; validate resource-limit behavior with that host configuration. Use rootless operation if supported and validated for the chosen combination.
2. Obtain an approved Debian-based Linux Ruby image pinned by digest, with Ruby compatible with the exercise Gemfile. Build from repository root:

   ```sh
   docker build --build-arg RUBY_BASE=APPROVED_REGISTRY_IMAGE_AT_DIGEST -f services/execution_worker/image/Dockerfile -t interview-rails-events:validation .
   docker image inspect interview-rails-events:validation --format '{{.Id}}'
   ```

   Replace the placeholder before running. Builds require registry/network access. The image now uses the committed generic-Ruby dependency lock with checksums and frozen Bundler installation, compiling native gems for Linux. Prefer the [pinned builder and deployment guide](../../deploy/linux-worker/README.md), which records image provenance. The current recipe has been built and validated inside the dedicated local Linux VM; see [live verification](../../deploy/local-vm/VERIFICATION.md).
3. Configure the returned immutable image ID as `INTERVIEW_WORKER_IMAGE`. Securely configure a random `INTERVIEW_WORKER_SIGNING_KEY` of at least 32 bytes for the trusted issuer and worker. Never send it in chat, job payloads, command arguments, or candidate environments.
4. Generate a signed starter/reference job with `make_example.py`, then pass it to `worker.py run` through stdin. Inspect receipts and verify expected 12-fail/12-pass behavior using the actual container output.
5. Run `worker.py reap` on an independent host watchdog at least every minute. A killed worker cannot run its own `finally` block. Its label deadline is execution start plus the configured timeout and ten seconds of cleanup grace; the watchdog runs after that deadline. It is a crash-recovery bound, not the normal command timeout.
6. Run the isolation, filesystem, cancellation, leak, and cost checks in the architecture decision before exposing execution.

The Docker control socket belongs only to the private worker. The browser and app-facing requests never get arbitrary access to it.

## Integration contract

Input is `{ "payload": { ... }, "signature": "hex HMAC-SHA256" }`. See `contracts.py` for the exact versioned schema and canonical serialization. The trusted issuer authenticates/authorizes the user, chooses exercise/version, applies quotas, and signs the job. The worker does not turn a claimed tenant UUID into proof of user authorization.

Output includes job/tenant/session IDs, source revision, execution status, exit code, bounded output, duration, truncation, and cleanup error. Treat output as untrusted text. `execution_completed` means the container process exited zero, not that an independent grader established correctness. Candidate code can influence same-process tests.

Per-host receipts prevent local replay. The Rails control plane now supplies centralized transactional leasing, idempotency, and one active lease per worker; PostgreSQL concurrency remains to be validated. Never describe the receipt store or lease protocol as fleet-wide exactly-once execution.

## Still required before production

- Real Linux/Docker/gVisor execution and adversarial isolation testing.
- Durable distributed job queue, leases/heartbeats, quota enforcement, cancellation control, and reconciliation.
- Authenticated transport between services and key rotation/revocation policy.
- External snapshot storage, workspace revisions, editor/PTY integration, and session reconnect.
- Authoritative grading outside candidate-controlled processes.
- Image provenance, Linux lockfile retention, vulnerability/compatibility review, and update policy.
- Monitoring, audit retention, backup/deletion, disk/log quotas, and independent watchdog deployment.

The Mac now has Docker tooling and a dedicated VM with runsc. `worker.py run` still refuses execution directly on macOS; the local transport runs that worker inside Linux rather than weakening the policy or using a host-process fallback.

Use `doctor.py` for read-only readiness checks, `build_image.py --plan` to inspect a pinned build, and the [live integration procedure](../../deploy/linux-worker/README.md) on an actual Linux host. Readiness checks do not establish sandbox security. The bridge validates the configured image before advertising capacity.

Official references: [gVisor Docker setup](https://gvisor.dev/docs/user_guide/quick_start/docker/), [Docker execution controls](https://docs.docker.com/engine/containers/run/), [Docker rootless mode](https://docs.docker.com/engine/security/rootless/).
