#!/usr/bin/env python3
"""Private worker process; JSON stdin/stdout. Never expose Docker to browsers."""
import argparse
import json
import os
from pathlib import Path
import re
import selectors
import signal
import shutil
import sqlite3
import subprocess
import sys
import time

from contracts import ContractError, MAX_JOB_BYTES, OPERATIONS, canonical, validate, verify

OUTPUT_LIMIT = 256 * 1024


class InfrastructureError(RuntimeError):
    pass


def docker_environment():
    # Do not forward application/service credentials into subprocess environments.
    env = {"PATH": os.defpath, "LANG": "C.UTF-8"}
    for key in ("DOCKER_HOST", "DOCKER_CONTEXT", "DOCKER_CONFIG", "XDG_RUNTIME_DIR", "HOME"):
        if key in os.environ:
            env[key] = os.environ[key]
    return env


def command_for(payload, image, docker="docker"):
    validate(payload)
    # Only a locally built immutable image ID. Never automatically pull job-supplied images.
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", image):
        raise ContractError("Configure a locally installed immutable Docker image ID")
    return [docker, "run", "--rm", "--pull=never", "--name", "interview-" + payload["job_id"],
            "--label", "interview.worker=execution-v1", "--label", "interview.job=" + payload["job_id"],
            "--label", "interview.expires-at=" + str(int(time.time()) + payload["timeout_seconds"] + 10),
            "--runtime=runsc", "--network=none", "--read-only", "--user=1000:1000",
            "--cpus=1", "--memory=2g", "--memory-swap=2g", "--pids-limit=128",
            "--cap-drop=ALL", "--security-opt=no-new-privileges=true",
            "--ulimit", "nofile=1024:1024", "--ulimit", "fsize=67108864:67108864",
            "--tmpfs", "/workspace:rw,exec,nosuid,nodev,size=256m,uid=1000,gid=1000,mode=0700",
            "--tmpfs", "/tmp:rw,noexec,nosuid,nodev,size=64m,uid=1000,gid=1000,mode=0700",
            "--workdir=/workspace", "--env=RAILS_ENV=test", "--env=HOME=/tmp",
            "--log-driver=none", "--interactive", "--entrypoint=ruby", image,
            *OPERATIONS[payload["exercise"]][1:]]


class Receipts:
    """Host-local durable replay protection; a future queue owns fleet-wide leases."""
    def __init__(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.path = path
        with sqlite3.connect(path) as db:
            db.execute("CREATE TABLE IF NOT EXISTS receipts (id TEXT PRIMARY KEY, status TEXT NOT NULL, result TEXT)")

    def claim(self, job_id):
        try:
            with sqlite3.connect(self.path) as db:
                db.execute("INSERT INTO receipts (id, status) VALUES (?, 'running')", (job_id,))
        except sqlite3.IntegrityError:
            raise ContractError("Job already claimed on this worker; use a new job ID for an explicit retry")

    def complete(self, job_id, result):
        with sqlite3.connect(self.path) as db:
            db.execute("UPDATE receipts SET status=?, result=? WHERE id=?",
                       (result["status"], json.dumps(result), job_id))


def preflight(docker):
    if sys.platform != "linux":
        raise InfrastructureError("Execution requires a dedicated Linux worker with Docker and runsc")
    result = subprocess.run([docker, "info", "--format", "{{json .}}"],
                            env=docker_environment(), capture_output=True, timeout=10)
    if result.returncode != 0:
        raise InfrastructureError("Docker daemon is unavailable")
    try:
        info = json.loads(result.stdout)
    except (ValueError, TypeError):
        raise InfrastructureError("Could not inspect configured Docker runtimes")
    runtimes = info.get("Runtimes", {})
    if "runsc" not in runtimes:
        raise InfrastructureError("runsc is required; refusing ordinary-runtime fallback")
    runtime_path = runtimes["runsc"].get("path", "")
    if Path(runtime_path).name != "runsc":
        raise InfrastructureError("Configured runsc runtime must point to a runsc executable")
    if info.get("OSType") != "linux":
        raise InfrastructureError("Docker daemon must be Linux")
    for capability in ("MemoryLimit", "PidsLimit", "CpuCfsQuota"):
        if info.get(capability) is not True:
            raise InfrastructureError(f"Docker does not report required {capability} support")
    return {key: info.get(key) for key in ("ServerVersion", "OSType", "Architecture", "CgroupVersion", "MemoryLimit", "PidsLimit", "CpuCfsQuota")}


def inspect_image(docker, image):
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", image):
        raise InfrastructureError("Worker image must be a local immutable image ID")
    result = subprocess.run([docker, "image", "inspect", image], env=docker_environment(),
                            capture_output=True, timeout=10)
    if result.returncode:
        raise InfrastructureError("Configured worker image is not installed")
    info = json.loads(result.stdout)[0]
    config = info.get("Config") or {}
    labels = config.get("Labels") or {}
    if info.get("Id") != image or info.get("Os") != "linux":
        raise InfrastructureError("Worker image identity or operating system does not match")
    if config.get("User") != "1000:1000" or labels.get("interview.contract") != "1" or labels.get("interview.exercise") != "rails.events.v1":
        raise InfrastructureError("Worker image does not declare the expected user/exercise contract")
    report = {key: info.get(key) for key in ("Id", "Os", "Architecture", "Created")}
    inventory = labels.get("interview.curriculum")
    if inventory == "rails-ruby-v1":
        report["operations"] = list(OPERATIONS)
    elif inventory == "rails-v1":
        report["operations"] = [operation for operation in OPERATIONS if operation.startswith("rails.")]
    else:
        report["operations"] = ["rails.events.v1", "rails.events.prepare.v1"]
    return report


def remove_container(docker, name):
    subprocess.run([docker, "rm", "--force", name], env=docker_environment(),
                   capture_output=True, timeout=10)
    # Absence is expected after --rm; inspect separately to verify cleanup.
    check = subprocess.run([docker, "container", "ls", "--all", "--filter", "name=^/" + name + "$", "--format", "{{.ID}}"],
                           env=docker_environment(), capture_output=True, timeout=10)
    if check.returncode or check.stdout.strip():
        raise InfrastructureError("Container cleanup could not be verified; operator action required")


def reap(docker, now=None):
    """Independent watchdog entrypoint; deletes only expired worker-owned containers."""
    now = int(time.time()) if now is None else now
    listing = subprocess.run([docker, "ps", "--all", "--filter", "label=interview.worker=execution-v1", "--format", "{{.ID}}"],
                             env=docker_environment(), capture_output=True, timeout=10)
    if listing.returncode:
        raise InfrastructureError("Cannot list containers for watchdog")
    removed = []
    for identity in listing.stdout.decode().split():
        if not re.fullmatch(r"[0-9a-f]{12,64}", identity):
            raise InfrastructureError("Invalid container identifier from daemon")
        inspected = subprocess.run([docker, "inspect", identity], env=docker_environment(),
                                   capture_output=True, timeout=10)
        if inspected.returncode:
            continue  # Concurrent cleanup may have already removed it.
        data = json.loads(inspected.stdout)[0]
        labels = data["Config"].get("Labels") or {}
        name = data["Name"].lstrip("/")
        job_id = labels.get("interview.job", "")
        if labels.get("interview.worker") != "execution-v1" or name != "interview-" + job_id:
            raise InfrastructureError("Watchdog ownership mismatch")
        if not re.fullmatch(r"[0-9a-f-]{36}", job_id):
            raise InfrastructureError("Invalid watchdog job label")
        deadline = int(labels["interview.expires-at"])
        if deadline <= now:
            remove_container(docker, name)
            removed.append(name)
    return removed


def execute(payload, image, docker):
    command = command_for(payload, image, docker)
    started = time.monotonic()
    process = None
    name = "interview-" + payload["job_id"]
    output = bytearray()
    stop_reason = None
    cleanup_error = None
    try:
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, env=docker_environment())
        # Feed bounded stdin on a separate thread so a blocked write cannot bypass the deadline.
        import threading
        input_errors = []

        def send_input():
            try:
                process.stdin.write(canonical({"files": payload["files"]}))
                process.stdin.close()
            except (BrokenPipeError, OSError) as error:
                input_errors.append(str(error))

        sender = threading.Thread(target=send_input, daemon=True)
        sender.start()
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)
        os.set_blocking(process.stdout.fileno(), False)
        while True:
            if time.monotonic() - started > payload["timeout_seconds"]:
                stop_reason = "timed_out"
                break
            events = selector.select(timeout=0.1)
            for key, _ in events:
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                    break
                remaining = OUTPUT_LIMIT - len(output)
                output.extend(chunk[:remaining])
                if len(chunk) > remaining:
                    stop_reason = "output_limit"
                    break
            if stop_reason or (process.poll() is not None and not selector.get_map()):
                break
        selector.close()
        if stop_reason:
            remove_container(docker, name)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
        sender.join(timeout=1)
        code = process.returncode
        status = stop_reason or ("execution_completed" if code == 0 else
                                 "infrastructure_error" if code in (70, 125, 126, 127) else "execution_failed")
    finally:
        try:
            remove_container(docker, name)
        except (InfrastructureError, subprocess.TimeoutExpired, OSError) as error:
            cleanup_error = str(error)
        if process is not None:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
            if process.stdout:
                process.stdout.close()
    return {"version": 1, "job_id": payload["job_id"], "tenant_id": payload["tenant_id"],
            "session_id": payload["session_id"], "source_revision": payload["source_revision"],
            "status": "infrastructure_error" if cleanup_error else status,
            "exit_code": code, "duration_seconds": round(time.monotonic() - started, 3),
            "output": output.decode("utf-8", errors="replace"), "output_truncated": stop_reason == "output_limit",
            "cleanup_error": cleanup_error,
            "grading_authority": "execution-evidence-only; candidate code can influence in-process tests"}


def main():
    def interrupted(signum, frame):
        raise InfrastructureError("Worker interrupted; cleaning up active container")
    signal.signal(signal.SIGTERM, interrupted)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["plan", "run", "reap"])
    parser.add_argument("--image", default=os.environ.get("INTERVIEW_WORKER_IMAGE", ""))
    parser.add_argument("--state", type=Path, default=Path(__file__).parent / ".state/receipts.sqlite3")
    args = parser.parse_args()
    if args.mode == "reap":
        docker = shutil.which("docker")
        if not docker:
            raise InfrastructureError("Docker executable is unavailable")
        preflight(docker)
        print(json.dumps({"removed": reap(docker)}))
        return
    raw = sys.stdin.buffer.read(MAX_JOB_BYTES + 1)
    if len(raw) > MAX_JOB_BYTES:
        raise ContractError("Job exceeds request size limit")
    envelope = json.loads(raw)
    if args.mode == "plan":
        payload = validate(envelope["payload"])
        print(json.dumps({"executed": False, "signature_verified": False,
                          "command": command_for(payload, args.image),
                          "source_revision": payload["source_revision"]}, indent=2))
        return
    secret = os.environ.get("INTERVIEW_WORKER_SIGNING_KEY", "")
    payload = verify(envelope, secret)
    command_for(payload, args.image)
    docker = shutil.which("docker")
    if not docker:
        raise InfrastructureError("Docker executable is unavailable")
    preflight(docker)
    inventory = inspect_image(docker, args.image)
    if payload["exercise"] not in inventory["operations"]:
        raise InfrastructureError("Exercise is not installed in this image")
    receipts = Receipts(args.state)
    receipts.claim(payload["job_id"])
    try:
        result = execute(payload, args.image, docker)
    except Exception:
        receipts.complete(payload["job_id"], {"status": "infrastructure_error"})
        raise
    receipts.complete(payload["job_id"], result)
    print(json.dumps(result))


if __name__ == "__main__":
    try:
        main()
    except (ContractError, InfrastructureError, ValueError, KeyError, OSError, subprocess.TimeoutExpired) as error:
        print(json.dumps({"status": "rejected", "error": str(error)}), file=sys.stderr)
        sys.exit(2)
