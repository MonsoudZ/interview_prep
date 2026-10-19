# Local Interview Studio Linux VM

Configured and validated on this Apple Silicon Mac on 2026-10-17. Railway remains the user's existing hosted provider; this VM is the local development execution environment and incurs no Railway sandbox usage.

## Installed and running

- Homebrew Colima 0.10.3, Lima 2.2.1, Docker CLI 29.9.0, and Docker Buildx 0.38.0.
- Dedicated `interview` Colima profile: Apple Virtualization framework (`vz`), ARM64, 2 CPUs, 4 GiB RAM, 8 GiB Docker data disk, and 6 GiB root disk. Disks are sparse; configured capacity is not the same as allocated host storage.
- Ubuntu 24.04.4 LTS, Linux 6.8.0-117-generic, Docker daemon 29.5.2, cgroup v2.
- gVisor `release-20261012.0`, installed from the complete official ARM64 archive after SHA-512 verification.
- No Mac directory mounts, no SSH-agent forwarding, no automatic Docker-context activation, and no automatic TCP port forwarding. The local Docker Unix socket is available through Colima's own SSH forwarding and must remain private.
- An independent cron watchdog runs the existing worker reaper every minute inside the VM.

The Mac has 16 GiB RAM. Free disk space was approximately 11 GiB before setup, 6.4 GiB after the image build, and 5.3 GiB at the end of validation. Keep at least 5 GiB free before further builds; the staging tool enforces that admission check. No user files were deleted to make room.

## Everyday use

From the repository root:

```sh
colima -p interview start
python3 services/local_vm/dev.py start
```

Open [Interview Studio](http://127.0.0.1:3100/). The development launcher starts the Rails server and private VM bridge using matching keys from an ignored mode-0600 configuration file. It does not deploy to Railway. If a separate app server already occupies port 3100, stop that server first; the launcher does not kill arbitrary processes.

The launcher runs in the foreground. Press Ctrl-C to stop its app and bridge, then stop the VM when finished:

```sh
colima -p interview stop
```

The VM keeps its image and data while stopped. Do not use `colima delete --data` unless you deliberately want to erase that VM's images and receipts. No login/startup service was enabled on the Mac; the VM starts on demand.

Inspect the VM or open its Linux shell:

```sh
colima -p interview status
colima -p interview ssh
```

The hosted app and local worker are separate processes. A future Railway-hosted app can use a local bridge over HTTPS while this Mac and VM are available; that is not an always-on execution fleet. No hosted app has been deployed yet.

## Actual image and proof

See [runtime.json](runtime.json) and [verification](VERIFICATION.md). The current image is:

```text
sha256:900545727221727f873a3283cb886c850aaf7b9692a47f08ae97fd248405cc50
```

The worker still requires Linux/Docker/gVisor. Its Linux-only check was not relaxed to make a Mac process look isolated. `services/local_vm/execute.py` sends the signed job, image ID, and signing key to the trusted VM entry point over SSH stdin. The key is not placed in a command argument, staged file, or candidate container. The original worker inside Linux verifies the signature/revision, inspects the image, applies policy, runs the job, records replay protection, and cleans up.

The authenticated local bridge polls Rails on loopback, advertises real VM/image readiness, leases jobs, keeps the heartbeat alive during work, and retries saved callbacks without rerunning code. Candidate Ruby executes only inside the no-network, read-only-root, non-root gVisor container. The Rails server on the Mac stores source text and results; it does not evaluate candidate files.

Private files are under `services/local_vm/.state/` (ignored by Git and Docker build context). `development.json` contains worker keys; `development.log` contains local server/bridge diagnostics. Do not share those files. Reinitialize only the image pointer while retaining existing keys:

```sh
python3 services/local_vm/dev.py init --image sha256:900545727221727f873a3283cb886c850aaf7b9692a47f08ae97fd248405cc50
```

## Recreate or update

For a fresh profile, the validated creation command is:

```sh
colima start interview --vm-type vz --arch aarch64 --cpus 2 --memory 4 --disk 8 --root-disk 6 --mount none --ssh-agent=false --ssh-config=false --activate=false --binfmt=false --port-forwarder none
```

In `~/.colima/interview/colima.yaml`, preserve the following Docker configuration. Colima regenerates Docker's daemon configuration on each boot; installing `runsc` inside Linux alone does not preserve its registration across restarts:

```yaml
docker:
  runtimes:
    runsc:
      path: /usr/local/bin/runsc
```

The existing profile has this setting. After changing it on a new profile, stop/start that profile so Colima applies it. Workers refuse ordinary-runtime fallback when gVisor is missing.

Bootstrap only the dedicated development VM, then stage the explicit trusted build context:

```sh
colima -p interview ssh -- bash -s < deploy/local-vm/bootstrap-linux.sh
python3 services/local_vm/stage.py
colima -p interview ssh -- sudo sh -c 'cat > /etc/cron.d/interview-worker-reap; chmod 0644 /etc/cron.d/interview-worker-reap; systemctl enable --now cron' < deploy/local-vm/interview-worker-reap.cron
```

The bootstrap selects the current official gVisor release and checks its published SHA-512. Record the resulting version/hash when updating; the version listed above is what was actually tested here. Staging includes only worker Python files, the guest entry point, the image recipe/lock, the shared starter template, explicit published exercise starters/test fixtures, and `.dockerignore`. It excludes application databases, accounts, saved submissions, local secrets, logs, and reference solutions. There is no shared home-directory shortcut.

Build the currently pinned Ruby base inside Linux:

```sh
colima -p interview ssh -- python3 /opt/interview/services/execution_worker/build_image.py --base ruby:4.0.1-slim@sha256:939bb2710ba0a49ffdba9470b4e562c9dfc5ee6718ba5a5214f1d421d0414d29
```

The builder records the resulting immutable image ID/provenance inside the VM. Use that actual new ID in the launcher configuration and live test. OS apt packages are not fully pinned; this is content-addressed execution, not a claim of bit-for-bit reproducible builds.

## Validation

From `apps/platform`:

```sh
RUN_LINUX_WORKER_INTEGRATION=1 INTERVIEW_COLIMA_PROFILE=interview INTERVIEW_WORKER_IMAGE=sha256:900545727221727f873a3283cb886c850aaf7b9692a47f08ae97fd248405cc50 ruby bin/rails test test/integration/live_worker_test.rb
```

This test passed with **3 runs, 330 assertions, zero failures/errors/skips**. It runs preparation, starter failures and reference success for all eight Rails repositories and Ruby intervals, observable isolation checks, callback/revision validation, and immutable submissions through the actual VM. It uses a synthetic account in the test database.

The separate browser/bridge check uses the local preview account and a clearly labeled reference attempt; it is not evidence of the user's interview performance. Adversarial escape testing, deliberate resource exhaustion, PostgreSQL concurrency, public-host deployment, voice, and calibrated AI review remain outside this verification.

Official references: [Colima installation](https://colima.run/docs/installation/), [Colima configuration](https://colima.run/docs/configuration/), [gVisor installation](https://gvisor.dev/docs/user_guide/install/), [gVisor Docker integration](https://gvisor.dev/docs/user_guide/quick_start/docker/).
