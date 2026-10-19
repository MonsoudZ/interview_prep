#!/usr/bin/env python3
"""Private Mac control-plane bridge; execution stays in the local Linux/gVisor VM."""
import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import threading
import uuid
from urllib.error import HTTPError

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "services/execution_worker"))
from bridge import check_url, request
from contracts import verify

# This filename also exists in execution_worker. Load the local transport by path.
import importlib.util
spec = importlib.util.spec_from_file_location("colima_execute", Path(__file__).with_name("execute.py"))
transport = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transport)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://127.0.0.1:3100")
    parser.add_argument("--profile", default="interview")
    parser.add_argument("--worker-id", required=True)
    parser.add_argument("--image", default=os.environ.get("INTERVIEW_WORKER_IMAGE", ""))
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()
    check_url(args.url)
    transport.command(args.profile)
    if str(uuid.UUID(args.worker_id)) != args.worker_id or not re.fullmatch(r"sha256:[0-9a-f]{64}", args.image):
        raise ValueError("Canonical worker UUID and immutable image required")
    bridge_key = os.environ.get("INTERVIEW_WORKER_BRIDGE_KEY", "")
    signing_key = os.environ.get("INTERVIEW_WORKER_SIGNING_KEY", "")
    if min(len(bridge_key.encode()), len(signing_key.encode())) < 32:
        raise ValueError("Securely configure both worker keys")
    stopping = threading.Event()
    def interrupted(signum, frame):
        stopping.set()
    for number in (signal.SIGTERM, signal.SIGINT):
        signal.signal(number, interrupted)
    state = ROOT / "services/local_vm/.state"
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    # Inspect inside Linux, rather than relaxing the worker's Linux-only policy.
    ready = subprocess.run(["colima", "-p", args.profile, "ssh", "--", "python3",
      "/opt/interview/services/execution_worker/doctor.py", "--image", args.image],
      capture_output=True, timeout=30)
    if ready.returncode:
        raise RuntimeError("VM host/image readiness check failed")
    capabilities = json.loads(ready.stdout)["image"]["operations"]
    def heartbeat():
        request(args.url, bridge_key, "/internal/workers/heartbeat", {
          "worker_id": args.worker_id, "capabilities": capabilities})
    def deliver(pending):
        data = json.loads(pending.read_text())
        try:
            request(args.url, bridge_key, "/internal/executions/" + data["result"]["job_id"] + "/result", data)
            pending.unlink()
        except HTTPError as error:
            if error.code not in (404, 409):
                raise
            pending.rename(pending.with_name(pending.name.replace("delivery-", "rejected-", 1)))
    def cycle():
        for pending in sorted(state.glob("delivery-*.json")):
            deliver(pending)
        heartbeat()
        leased = request(args.url, bridge_key, "/internal/workers/lease", {"worker_id": args.worker_id})
        if leased.get("job"):
            payload = verify(leased["job"], signing_key)
            stop_heartbeat = threading.Event()
            def keep_alive():
                while not stop_heartbeat.wait(15):
                    try:
                        heartbeat()
                    except Exception:
                        pass
            thread = threading.Thread(target=keep_alive, daemon=True)
            thread.start()
            try:
                output = transport.run(leased["job"], signing_key, args.image, args.profile)
                if output.returncode:
                    raise RuntimeError("VM execution transport failed")
                result = json.loads(output.stdout)
            except Exception:
                result = {field: payload[field] for field in ("job_id", "tenant_id", "session_id", "source_revision")}
                result.update(version=1, status="infrastructure_error", exit_code=None,
                  output="Local VM execution was interrupted. No successful candidate result was confirmed.")
            finally:
                stop_heartbeat.set()
                thread.join(timeout=16)
            pending = state / ("delivery-" + payload["job_id"] + ".json")
            fd = os.open(pending, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w") as stream:
                json.dump({"lease_token": leased["lease_token"], "result": result}, stream)
                stream.flush()
                os.fsync(stream.fileno())
            deliver(pending)
            print(json.dumps({"job_id": payload["job_id"], "status": result["status"]}), flush=True)

    failures = 0
    while not stopping.is_set():
        try:
            cycle()
            failures = 0
        except Exception as error:
            # A transient control-plane or network error must not stop the worker. Persisted
            # deliveries are retried on the next cycle and unfinished leases expire server-side.
            if args.once or stopping.is_set():
                raise
            failures += 1
            print(json.dumps({"status": "bridge_retrying", "attempt": failures, "error": str(error)}), file=sys.stderr, flush=True)
        if args.once:
            return
        if stopping.wait(min(60, 2 * 2 ** min(failures, 5)) if failures else 2):
            return


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print("Local VM bridge stopped; inspect the app connection and VM readiness", file=sys.stderr)
        sys.exit(2)
