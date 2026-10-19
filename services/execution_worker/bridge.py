#!/usr/bin/env python3
"""Private Linux worker polls the Rails control plane; no public execution API."""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import sys
import threading
import time
from urllib.parse import urlparse
from urllib.request import Request, HTTPRedirectHandler, build_opener
from urllib.error import HTTPError
import uuid

from contracts import canonical, verify
from worker import InfrastructureError, Receipts, command_for, execute, preflight, inspect_image


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError("Control-plane redirects are not allowed; credentials remain scoped to the configured origin")


def request(base, key, path, data):
    req = Request(base.rstrip("/") + path, data=canonical(data), method="POST",
                  headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    with build_opener(NoRedirect()).open(req, timeout=15) as response:
        return json.loads(response.read(2 * 1024 * 1024))


def check_url(value):
    parsed = urlparse(value)
    if parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.path not in ("", "/"):
        raise ValueError("Use an origin URL without credentials, path, query, or fragment")
    if parsed.scheme != "https" and not (parsed.scheme == "http" and parsed.hostname in ("127.0.0.1", "localhost", "::1")):
        raise ValueError("Worker bridge requires HTTPS except for loopback development")
    if not parsed.hostname:
        raise ValueError("Missing control-plane host")


def main():
    stopping = threading.Event()
    def interrupted(signum, frame):
        stopping.set()
        raise InfrastructureError("Bridge interrupted; cleaning up execution")
    signal.signal(signal.SIGTERM, interrupted)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True)
    parser.add_argument("--worker-id", required=True)
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--state", type=Path, default=Path(__file__).parent / ".state")
    args = parser.parse_args()
    check_url(args.url)
    if str(uuid.UUID(args.worker_id)) != args.worker_id:
        raise ValueError("Worker ID must be a canonical UUID")
    bridge_key = os.environ.get("INTERVIEW_WORKER_BRIDGE_KEY", "")
    signing_key = os.environ.get("INTERVIEW_WORKER_SIGNING_KEY", "")
    image = os.environ.get("INTERVIEW_WORKER_IMAGE", "")
    if min(len(bridge_key.encode()), len(signing_key.encode())) < 32:
        raise ValueError("Securely configure both worker keys (32 bytes minimum each)")
    docker = shutil.which("docker")
    if not docker:
        raise InfrastructureError("Docker is not installed; no host-execution fallback")
    preflight(docker)
    inventory = inspect_image(docker, image)
    args.state.mkdir(parents=True, exist_ok=True, mode=0o700)
    receipts = Receipts(args.state / "receipts.sqlite3")

    def heartbeat():
        return request(args.url, bridge_key, "/internal/workers/heartbeat", {
            "worker_id": args.worker_id, "capabilities": inventory["operations"]})

    while True:
        # Deliver persisted results before asking for another lease.
        for pending in sorted(args.state.glob("delivery-*.json")):
            data = json.loads(pending.read_text())
            try:
                request(args.url, bridge_key, "/internal/executions/" + data["result"]["job_id"] + "/result", data)
                pending.unlink()
            except HTTPError as error:
                if error.code not in (404, 409):
                    raise
                pending.rename(pending.with_name(pending.name.replace("delivery-", "rejected-", 1)))
                print(json.dumps({"job_id": data["result"]["job_id"], "status": "delivery_rejected", "http_status": error.code}), file=sys.stderr)
        heartbeat()
        leased = request(args.url, bridge_key, "/internal/workers/lease", {"worker_id": args.worker_id})
        if leased.get("job"):
            payload = verify(leased["job"], signing_key)
            command_for(payload, image, docker)
            receipts.claim(payload["job_id"])
            stop = threading.Event()

            def keep_alive():
                while not stop.wait(15):
                    try:
                        heartbeat()
                    except Exception:
                        pass  # Job remains bounded by worker deadline and control-plane lease.

            thread = threading.Thread(target=keep_alive, daemon=True)
            thread.start()
            try:
                result = execute(payload, image, docker)
            except Exception:
                result = {key: payload[key] for key in ("job_id", "tenant_id", "session_id", "source_revision")}
                result.update(version=1, status="infrastructure_error", exit_code=None,
                              output="Execution worker failed. Inspect private host diagnostics.")
            finally:
                stop.set()
                thread.join(timeout=16)
            receipts.complete(payload["job_id"], result)
            delivery = {"lease_token": leased["lease_token"], "result": result}
            pending = args.state / ("delivery-" + payload["job_id"] + ".json")
            fd = os.open(pending, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w") as stream:
                json.dump(delivery, stream)
                stream.flush()
                os.fsync(stream.fileno())
            request(args.url, bridge_key, "/internal/executions/" + payload["job_id"] + "/result", delivery)
            pending.unlink()
            print(json.dumps({"job_id": payload["job_id"], "status": result["status"]}), flush=True)
            if stopping.is_set():
                return
        if args.once:
            return
        time.sleep(2)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(json.dumps({"status": "bridge_stopped", "error": str(error)}), file=sys.stderr)
        sys.exit(2)
