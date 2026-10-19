#!/usr/bin/env python3
"""Mac transport to the private Colima worker. Candidate code runs only in gVisor."""
import argparse
import json
import os
import re
import subprocess
import sys


def command(profile):
    if not re.fullmatch(r"[a-z][a-z0-9-]{0,31}", profile):
        raise ValueError("Invalid Colima profile")
    return ["colima", "-p", profile, "ssh", "--", "python3", "/opt/interview/services/local_vm/guest.py"]


def run(envelope, signing_key, image, profile="interview"):
    if len(signing_key.encode()) < 32:
        raise ValueError("Signing key must be securely configured")
    frame = {"job": envelope, "signing_key": signing_key, "image": image}
    # No secrets in arguments, command text, or a VM filesystem. Never invoke a shell.
    return subprocess.run(command(profile), input=json.dumps(frame).encode(),
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=100)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", default="interview")
    parser.add_argument("--image", default=os.environ.get("INTERVIEW_WORKER_IMAGE", ""))
    args = parser.parse_args()
    raw = sys.stdin.buffer.read(2 * 1024 * 1024 + 1)
    if len(raw) > 2 * 1024 * 1024:
        raise ValueError("Job limit exceeded")
    outcome = run(json.loads(raw), os.environ.get("INTERVIEW_WORKER_SIGNING_KEY", ""), args.image, args.profile)
    sys.stdout.buffer.write(outcome.stdout)
    if outcome.returncode:
        print("VM worker did not return a successful transport result", file=sys.stderr)
    raise SystemExit(outcome.returncode)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print("Local VM transport failed; candidate code was not executed on the Mac", file=sys.stderr)
        sys.exit(2)
