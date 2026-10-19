#!/usr/bin/env python3
"""Start the local Rails studio and its VM bridge with private matching keys."""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import signal
import socket
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
STATE = Path(__file__).parent / ".state"
CONFIG = STATE / "development.json"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["init", "start"])
    parser.add_argument("--image")
    parser.add_argument("--review-model", help="Installed local Ollama model; init stores it, start may override it")
    parser.add_argument("--review-context", type=int, choices=[32768,65536])
    args = parser.parse_args()
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    if args.mode == "init":
        if not args.image or not re.fullmatch(r"sha256:[0-9a-f]{64}", args.image):
            raise ValueError("Supply the actual immutable VM image ID")
        if CONFIG.exists():
            data = json.loads(CONFIG.read_text())
            data["image"] = args.image
            if args.review_model:
                data["review_model"] = args.review_model
            if args.review_context:
                data["review_context"] = args.review_context
            data.setdefault("review_bridge_key", secrets.token_hex(32))
            data.setdefault("review_worker_id", str(uuid.uuid4()))
            temporary = CONFIG.with_suffix(".tmp")
            with os.fdopen(os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as stream:
                json.dump(data, stream)
            temporary.replace(CONFIG)
        else:
            data = {"profile": "interview", "image": args.image, "worker_id": str(uuid.uuid4()),
              "bridge_key": secrets.token_hex(32), "signing_key": secrets.token_hex(32),
              "review_bridge_key": secrets.token_hex(32), "review_worker_id": str(uuid.uuid4()),
              "review_model": args.review_model, "review_context": args.review_context or 32768}
            with os.fdopen(os.open(CONFIG, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as stream:
                json.dump(data, stream)
        print("Private local worker configuration saved (keys not displayed)")
        return

    data = json.loads(CONFIG.read_text())
    # Older local configurations remain usable without silently enabling a model.
    if "review_bridge_key" not in data:
        data["review_bridge_key"] = secrets.token_hex(32)
        data["review_worker_id"] = str(uuid.uuid4())
        temporary = CONFIG.with_suffix(".tmp")
        with os.fdopen(os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as stream:
            json.dump(data, stream)
        temporary.replace(CONFIG)
    probe = socket.socket()
    probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        probe.bind(("127.0.0.1", 3100))
    except OSError:
        raise RuntimeError("Port 3100 is already in use; stop the existing local studio before starting this launcher")
    finally:
        probe.close()
    env = os.environ.copy()
    env.update(INTERVIEW_WORKER_BRIDGE_KEY=data["bridge_key"], INTERVIEW_WORKER_SIGNING_KEY=data["signing_key"], INTERVIEW_WORKER_IMAGE=data["image"])
    env["INTERVIEW_REVIEW_BRIDGE_KEY"] = data["review_bridge_key"]
    if data.get("app_secret"):
        env["SECRET_KEY_BASE"] = data["app_secret"]
    if data.get("cookie_name"):
        env["INTERVIEW_COOKIE_NAME"] = data["cookie_name"]
    children = []
    optional_children = []
    stopping = False
    def stop(signum=None, frame=None):
        nonlocal stopping
        stopping = True
        for child in reversed(children + optional_children):
            if child.poll() is None:
                child.terminate()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    log_path = STATE / "development.log"
    fd = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    with os.fdopen(fd, "a") as log:
        try:
            app = subprocess.Popen(["ruby", "bin/rails", "server", "-b", "127.0.0.1", "-p", "3100"], cwd=ROOT / "apps/platform", env=env, stdout=log, stderr=log)
            children.append(app)
            for attempt in range(60):
                if app.poll() is not None or stopping:
                    raise RuntimeError("Rails could not start; inspect the private development log")
                try:
                    with socket.create_connection(("127.0.0.1", 3100), timeout=1):
                        break
                except OSError:
                    time.sleep(0.5)
            else:
                raise RuntimeError("Rails did not become ready")
            worker = subprocess.Popen([sys.executable, str(Path(__file__).with_name("bridge.py")),
              "--worker-id", data["worker_id"], "--profile", data["profile"], "--image", data["image"]], cwd=ROOT, env=env, stdout=log, stderr=log)
            children.append(worker)
            model = args.review_model or data.get("review_model")
            if model:
                review_command = [sys.executable, str(ROOT / "services/review_worker/worker.py"),
                    "--worker-id", data["review_worker_id"], "--model", model,
                    "--context", str(args.review_context or data.get("review_context", 32768))]
                try:
                    ready = subprocess.run(review_command + ["--doctor"], env=env, stdout=log, stderr=log, timeout=20).returncode == 0
                except subprocess.TimeoutExpired:
                    ready = False
                if ready:
                    optional_children.append(subprocess.Popen(review_command, cwd=ROOT, env=env, stdout=log, stderr=log))
                else:
                    print("Studio model unavailable; interview practice remains available. Connect Ollama and restart to enable reviews.", flush=True)
            print("Interview Studio: http://127.0.0.1:3100/ — local Linux VM worker starting", flush=True)
            while not stopping:
                if any(child.poll() is not None for child in children):
                    raise RuntimeError("A development process stopped; inspect the private development log")
                time.sleep(1)
        finally:
            stop()
            for child in reversed(children + optional_children):
                try:
                    child.wait(timeout=110)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=5)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(2)
