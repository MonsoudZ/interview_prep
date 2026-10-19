#!/usr/bin/env python3
"""Trusted VM entry point: secret and signed job arrive only over SSH stdin."""
import json
from pathlib import Path
import shutil
import signal
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "services/execution_worker"))
from contracts import verify, MAX_JOB_BYTES
from worker import Receipts, preflight, inspect_image, execute


def main():
    def interrupted(signum, frame):
        raise RuntimeError("VM transport interrupted; cleaning up active container")
    for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(signum, interrupted)
    raw = sys.stdin.buffer.read(MAX_JOB_BYTES + 8193)
    if len(raw) > MAX_JOB_BYTES + 8192:
        raise ValueError("Request limit exceeded")
    frame = json.loads(raw)
    if set(frame) != {"job", "signing_key", "image"}:
        raise ValueError("Invalid trusted transport frame")
    payload = verify(frame["job"], frame["signing_key"])
    docker = shutil.which("docker")
    if not docker:
        raise ValueError("Docker unavailable in VM")
    preflight(docker)
    inventory = inspect_image(docker, frame["image"])
    if payload["exercise"] not in inventory["operations"]:
        raise ValueError("Exercise is not installed in this image")
    receipts = Receipts(ROOT / "services/execution_worker/.state/receipts.sqlite3")
    receipts.claim(payload["job_id"])
    try:
        result = execute(payload, frame["image"], docker)
    except Exception:
        receipts.complete(payload["job_id"], {"status": "infrastructure_error"})
        raise
    receipts.complete(payload["job_id"], result)
    print(json.dumps(result))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Provider/transport exceptions must not expose the secret input frame.
        print(json.dumps({"status": "infrastructure_error", "error": "VM worker could not complete; inspect runtime configuration"}), file=sys.stderr)
        sys.exit(2)
