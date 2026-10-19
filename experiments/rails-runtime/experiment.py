#!/usr/bin/env python3
"""Trusted local Rails runtime experiment. NOT a sandbox or grading service."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parent
WORK = ROOT / ".work"
SKIP = {"storage", "log", "tmp", ".bundle"}


def manifest(directory):
    entries = {}
    for path in sorted(directory.rglob("*")):
        relative = path.relative_to(directory)
        if any(part in SKIP for part in relative.parts):
            continue
        if path.is_symlink():
            raise ValueError(f"Symlinks are unsupported in this trusted experiment: {relative}")
        if path.is_file():
            entries[str(relative)] = hashlib.sha256(path.read_bytes()).hexdigest()
    return entries


def copy_sources(source, target):
    for name in manifest(source):
        destination = target / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / name, destination)


def execute(command, cwd, ruby, timeout=30):
    # Minimize inherited environment; this is hygiene, not a security boundary.
    env = {
        "PATH": str(Path(ruby).parent) + os.pathsep + os.defpath,
        "RAILS_ENV": "test", "BUNDLE_GEMFILE": str(cwd / "Gemfile"),
        "BUNDLE_APP_CONFIG": str(cwd / ".bundle"), "LANG": "en_US.UTF-8",
    }
    started = time.monotonic()
    process = subprocess.Popen(command, cwd=cwd, env=env, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, start_new_session=True)
    timed_out = False
    try:
        output, _ = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        os.killpg(process.pid, signal.SIGKILL)
        output, _ = process.communicate()
    text = output.decode("utf-8", errors="replace")
    counts = re.search(r"(\d+) runs, (\d+) assertions, (\d+) failures, (\d+) errors, (\d+) skips", text)
    return {
        "exit_code": process.returncode,
        "timed_out": timed_out,
        "duration_seconds": round(time.monotonic() - started, 3),
        "counts": dict(zip(("runs", "assertions", "failures", "errors", "skips"), map(int, counts.groups()))) if counts else None,
        "output": text,
    }


def require_success(result, label):
    if result["exit_code"] != 0 or result["timed_out"]:
        raise RuntimeError(f"{label} failed:\n{result['output']}")


def tests(workspace, ruby):
    return execute([ruby, "-Itest", "test/integration/events_test.rb"], workspace, ruby)


def checkpoint(workspace, directory):
    directory.mkdir(parents=True, exist_ok=False)
    copy_sources(workspace, directory / "source")
    entries = manifest(directory / "source")
    identity = hashlib.sha256(json.dumps(entries, sort_keys=True).encode()).hexdigest()
    (directory / "manifest.json").write_text(json.dumps({"revision": identity, "files": entries}, indent=2) + "\n")
    return identity


def restore(directory, destination):
    saved = json.loads((directory / "manifest.json").read_text())
    entries = manifest(directory / "source")
    identity = hashlib.sha256(json.dumps(entries, sort_keys=True).encode()).hexdigest()
    if saved["files"] != entries or saved["revision"] != identity:
        raise ValueError("Checkpoint integrity check failed")
    destination.mkdir(parents=True, exist_ok=False)
    copy_sources(directory / "source", destination)
    return saved["revision"]


def demo(ruby):
    run_id = str(uuid.uuid4())
    run_root = WORK / run_id
    workspace = run_root / "workspace"
    workspace.mkdir(parents=True)
    started = time.monotonic()
    copy_sources(ROOT / "template", workspace)
    preparation = execute([ruby, "bin/prepare.rb"], workspace, ruby)
    require_success(preparation, "Starter readiness")
    readiness_seconds = round(time.monotonic() - started, 3)
    starter = tests(workspace, ruby)
    if not starter["counts"] or starter["counts"]["runs"] != 12 or starter["counts"]["failures"] != 12:
        raise RuntimeError(f"Expected 12 starter assertion failures:\n{starter['output']}")

    copy_sources(ROOT / "reference", workspace)
    reference = tests(workspace, ruby)
    require_success(reference, "Reference tests")
    if reference["counts"]["runs"] != 12:
        raise RuntimeError("Expected exactly 12 reference tests")
    revision = checkpoint(workspace, run_root / "checkpoint")

    # A real controller edit must be detected by the test suite.
    controller = workspace / "app/controllers/events_controller.rb"
    controller.write_text(controller.read_text().replace("status: :created", "status: :ok"))
    broken = tests(workspace, ruby)
    if broken["exit_code"] == 0 or not broken["counts"] or broken["counts"]["failures"] == 0:
        raise RuntimeError("Deliberate HTTP status regression was not detected")

    # Restore into a new directory, with a fresh process and rebuilt database.
    recovered = run_root / "recovered"
    recovered_revision = restore(run_root / "checkpoint", recovered)
    preparation_recovered = execute([ruby, "bin/prepare.rb"], recovered, ruby)
    require_success(preparation_recovered, "Recovered readiness")
    recovered_tests = tests(recovered, ruby)
    require_success(recovered_tests, "Recovered tests")
    assert recovered_revision == revision
    assert manifest(recovered) == manifest(run_root / "checkpoint/source")

    # Guard against trusting changed snapshots.
    snapshot_controller = run_root / "checkpoint/source/app/controllers/events_controller.rb"
    original = snapshot_controller.read_bytes()
    snapshot_controller.write_bytes(original + b"\n# tampered\n")
    try:
        restore(run_root / "checkpoint", run_root / "must-not-restore")
    except ValueError:
        integrity_rejected = True
    else:
        raise RuntimeError("Tampered checkpoint accepted")
    finally:
        snapshot_controller.write_bytes(original)

    timed = execute([ruby, "-e", "sleep 10"], workspace, ruby, timeout=0.2)
    assert timed["timed_out"] and timed["exit_code"] != 0
    report = {
        "run_id": run_id, "scope": "trusted-local-processes-only",
        "ruby": execute([ruby, "--version"], workspace, ruby)["output"].strip(),
        "readiness_seconds": readiness_seconds, "checkpoint_revision": revision,
        "starter": starter, "reference": reference, "regression": broken,
        "recovered": recovered_tests, "recovery_preparation": preparation_recovered,
        "tampered_checkpoint_rejected": integrity_rejected, "timeout": timed,
        "limitations": ["No OS/container security isolation", "No hosted startup or network measurements",
                        "Source recovery only; database recreated from schema", "No browser editor or terminal synchronization",
                        "Local installed-gem dependency cache", "Captured output is not production-bounded"],
    }
    result_path = ROOT / "results/latest.json"
    result_path.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"result": str(result_path), "readiness_seconds": readiness_seconds,
                      "starter": starter["counts"], "reference": reference["counts"],
                      "regression": broken["counts"], "recovered": recovered_tests["counts"],
                      "integrity_rejected": integrity_rejected, "timeout_verified": timed["timed_out"]}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["demo"])
    parser.add_argument("--ruby", required=True, help="Absolute path to a real Ruby executable (not a shim)")
    args = parser.parse_args()
    ruby_path = Path(args.ruby)
    if not ruby_path.is_absolute() or not ruby_path.is_file():
        parser.error("--ruby must be an existing absolute executable path")
    demo(str(ruby_path))
