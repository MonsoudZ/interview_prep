#!/usr/bin/env python3
"""Build and record a pinned worker image. Never provisions a server."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import time
import uuid

from worker import docker_environment, preflight, inspect_image

ROOT = Path(__file__).resolve().parents[2]


def build_command(docker, base, iidfile=None):
    if not re.fullmatch(r"(?:docker\.io/library/)?ruby(?::[A-Za-z0-9_.-]+)?@sha256:[0-9a-f]{64}", base):
        raise ValueError("Use an official Ruby image pinned by sha256 digest, not a floating tag")
    return [docker, "build", "--build-arg", "RUBY_BASE=" + base, "--iidfile",
            str(iidfile or ROOT / "services/execution_worker/.state/build/plan-image-id"),
            "-f", str(ROOT / "services/execution_worker/image/Dockerfile"), str(ROOT)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True)
    parser.add_argument("--plan", action="store_true")
    args = parser.parse_args()
    docker = shutil.which("docker") or "docker"
    command = build_command(docker, args.base)
    lock = ROOT / "services/execution_worker/image/dependencies/Gemfile.lock"
    plan = {"executed": False, "command": command, "dependency_lock_sha256": hashlib.sha256(lock.read_bytes()).hexdigest()}
    if args.plan:
        print(json.dumps(plan, indent=2))
        return
    daemon = preflight(docker)
    output = ROOT / "services/execution_worker/.state/build" / str(uuid.uuid4())
    output.mkdir(parents=True, exist_ok=True, mode=0o700)
    command = build_command(docker, args.base, output / "image-id")
    started = time.monotonic()
    with (output / "build.log").open("w") as log:
        subprocess.run(command, env=docker_environment(), stdout=log, stderr=subprocess.STDOUT, check=True, timeout=1800)
    image = (output / "image-id").read_text().strip()
    inspected = inspect_image(docker, image)
    report = {"executed": True, "base_image": args.base, "image": inspected, "daemon": daemon,
              "dependency_lock_sha256": plan["dependency_lock_sha256"],
              "duration_seconds": round(time.monotonic() - started, 3), "live_rails_tested": False}
    (output / "provenance.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
