#!/usr/bin/env python3
"""Copy an explicit trusted build context to the VM; never share the Mac home."""
import argparse
import io
from pathlib import Path
import shutil
import subprocess
import tarfile

from execute import command

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", default="interview")
    args = parser.parse_args()
    if shutil.disk_usage(ROOT).free < 5 * 1024 ** 3:
        raise RuntimeError("Keep at least 5 GiB free on the Mac before staging/building the VM image")
    paths = [ROOT / ".dockerignore", ROOT / "services/execution_worker/image",
      ROOT / "experiments/rails-runtime/template", ROOT / "services/local_vm/guest.py"]
    paths += [ROOT / "curriculum/rails" / slug / "starter" for slug in
              ("tenant-projects", "idempotent-checkout", "delivery-retries", "activity-feed")]
    paths += [ROOT / "curriculum/ruby/merge-intervals/starter", ROOT / "curriculum/ruby/merge-intervals/hidden_test.rb"]
    paths += sorted((ROOT / "services/execution_worker").glob("*.py"))
    buffer = io.BytesIO()
    excluded = {"__pycache__", ".state", ".git", "log", "storage", "tmp"}
    def trusted_entry(info):
        parts = Path(info.name).parts
        if info.issym() or info.islnk() or excluded.intersection(parts) or any(part == ".env" or part.startswith(".env.") for part in parts):
            return None
        return info
    with tarfile.open(fileobj=buffer, mode="w") as archive:
        for path in paths:
            archive.add(path, arcname=str(path.relative_to(ROOT)), filter=trusted_entry)
    script = 'sudo mkdir -p /opt/interview && sudo chown "$(id -u):$(id -g)" /opt/interview && tar -xf - -C /opt/interview'
    ssh = command(args.profile)[:-2] + ["sh", "-c", script]
    subprocess.run(ssh, input=buffer.getvalue(), check=True, timeout=30)
    print("Trusted worker/image/template files staged; no Mac directories are mounted")


if __name__ == "__main__":
    main()
