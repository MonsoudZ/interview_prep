# Dedicated Linux development worker

Standalone-host deployment recipe. These systemd units have not been installed or exercised. The [local Colima VM path](../local-vm/README.md) is now configured and verified; use that guide for development on this Mac. This is not production certification.

## Recommended environment

This is an optional deployment path for an existing Linux host. The current user constraint is Railway-only hosting with no additional paid services, so do not buy a host to follow this guide. See [ADR 002](../../docs/decisions/002-railway-only-budget.md) for the proposed Railway Sandboxes direction.

For an existing dedicated Linux development host, connect to the application over an authenticated, encrypted route. Proposed sizing is 2 vCPU, 4 GiB RAM, and 40 GiB disk for one 2-GiB sandbox at a time; measure builds and runtime use. This is a resource proposal, not a provider capacity guarantee or price quote.

On 2026-10-17 the user selected a local VM. A small sparse-disk Colima profile was created and the real image/test flow passed; free Mac storage was about 6.4 GiB after building. No paid server is authorized by this document.

## Prerequisites and host preparation

1. Choose a Linux host/region and approve its spend before provisioning. Keep worker and platform/database infrastructure separate for deployed use.
2. Install Docker Engine from its official distribution and gVisor using the current [official installation instructions](https://gvisor.dev/docs/user_guide/install/). Current gVisor documentation specifies Linux 5.6+ and supports x86_64/ARM64. Package installations include companion files; do not copy an old standalone binary recipe blindly.
3. Configure Docker's `runsc` runtime per the [official Docker integration guide](https://gvisor.dev/docs/user_guide/quick_start/docker/). The worker rejects a missing runtime, a `runsc` alias pointing to another executable name, or a daemon that does not report CPU/memory/PID limit support. This detects configuration mistakes, not malicious host administration.
4. Create a dedicated service account and copy the repository to `/opt/interview-prep`, readable by that account and writable only by trusted deployers. Do not copy application databases, `.state`, credentials, or build logs. Protect the Docker socket; access to it is a privileged host capability. The sample units use the Docker group only on this dedicated execution host. Rootless operation is a separate configuration that requires testing.
5. Do not expose the Docker API, candidate containers, or worker service publicly. The worker initiates requests to the control plane. Keep `/internal/` routes restricted and use HTTPS; for isolated integration checks a loopback SSH tunnel may be used. Never disable certificate verification.

## Build

Use an official Debian-based Ruby image compatible with Ruby 4.0.1, selected and pinned by its actual registry digest. Do not use the illustrative hash below as an image.

```sh
python3 services/execution_worker/build_image.py --base ruby@sha256:ACTUAL_APPROVED_DIGEST
```

The builder first requires a Linux Docker/runsc environment. It uses the committed generic-Ruby dependency lock with frozen Bundler installation. Native gems compile for the selected Linux architecture. Base image and resulting immutable image ID, lock hash, host metadata, and build time are recorded under `.state/build/`. OS package updates are not fully pinned, so this does not promise bit-for-bit reproducibility; the resulting image ID identifies what will execute.

For command inspection without a host/build, use `--plan` with a syntactically valid illustrative digest. Plan mode reports `executed: false`.

## Readiness and live integration

Configure `INTERVIEW_WORKER_IMAGE` to the actual built image ID, then:

```sh
python3 services/execution_worker/doctor.py
```

`ready: true` means the declared host/image prerequisites pass. It does not mean Rails execution or isolation tests passed.

On the isolated Linux validation environment with Ruby, Python, the platform's gems, and the worker image available:

```sh
cd apps/platform
RAILS_ENV=test ruby bin/rails db:prepare
RUN_LINUX_WORKER_INTEGRATION=1 ruby bin/rails test test/integration/live_worker_test.rb
```

The live test operates against Rails' test database and uses synthetic test accounts. It exercises real request handling, database queueing, job signing, Python verification, Docker/gVisor execution, callback handling, revision matching, and immutable submission. It checks preparation, 12 starter failures, and 12 reference successes/158 assertions. Trusted probes observe non-root UID, absent Docker socket, inability to write an image path, and a blocked external IPv4 TCP connection.

Missing Linux/Docker/image/runsc fails an explicitly enabled test. An ordinary local run leaves this opt-in test skipped, which must never be reported as successful live validation. The test uses in-process Rails requests, not a networked browser or the long-running bridge daemon; those remain additional integration checks. Observations do not establish protection against all attacks or protocols. Add memory/CPU/PID enforcement, neighbor/host access, cancellation, host failure, and recovery checks before untrusted public use.

## Run the bridge and watchdog

1. Securely create `/etc/interview-worker/environment` using `environment.example` as the field list. Generate two different high-entropy secrets; keep them out of shell history, command arguments, chat, and source control. Configure the corresponding secrets in the platform process. Store a stable canonical worker UUID and the actual image ID.
2. Install the sample service/timer files after inspecting paths and permissions. Set file ownership to root and restrict the environment file to the necessary service account/group. Create no login-enabled account for candidate code.
3. Enable/start the bridge and reaper timer through the host's service manager. No install/start commands have been executed here.
4. Verify heartbeats, queue dispatch, callback acceptance, and bounded test output. Rejected/expired pending deliveries are retained as `rejected-*.json` for operator review; credentials in those files require restrictive permissions.
5. Confirm the independently scheduled watchdog deletes an expired test container if the bridge is killed. Normal shutdown requests clean up active containers; hard crashes still require the watchdog. Container deadlines are set from execution start plus the configured timeout and ten seconds of cleanup grace.

The bridge's systemd memory/task limit bounds the control process, not Docker-managed candidate cgroups; Docker policies bound each sandbox separately. Independent host monitoring and capacity protection remain required.

## Deployment status

Completed locally: Linux-compatible gem lock, frozen image recipe, pinned-image builder, host/image doctor, runtime-path/capability checks, bridge shutdown/delivery handling, opt-in live Rails integration, and service/watchdog templates.

Completed through the local VM: image build, actual Linux/gVisor execution, Rails live integration, browser/bridge execution, and cron-based cleanup. Still unverified: these standalone systemd units, hosted networking/TLS, adversarial/load tests, production operations, and cloud execution provisioning.
