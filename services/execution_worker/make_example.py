#!/usr/bin/env python3
"""Create a fresh starter/reference job. Prints no signing secrets."""
import argparse
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import time
import uuid

from contracts import canonical, revision, validate

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--reference", action="store_true")
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
source = root / "experiments/rails-runtime" / ("reference" if args.reference else "template")
files = {str(path.relative_to(source)): base64.b64encode(path.read_bytes()).decode()
         for path in sorted((source / "app").rglob("*.rb"))}
now = int(time.time())
payload = {"version": 1, "job_id": str(uuid.uuid4()), "tenant_id": str(uuid.uuid4()),
           "session_id": str(uuid.uuid4()), "exercise": "rails.events.v1", "issued_at": now,
           "expires_at": now + 300, "timeout_seconds": 60, "files": files,
           "source_revision": revision(files)}
validate(payload)
secret = os.environ.get("INTERVIEW_WORKER_SIGNING_KEY")
signature = hmac.new(secret.encode(), canonical(payload), hashlib.sha256).hexdigest() if secret else "unsigned-plan-only"
print(json.dumps({"payload": payload, "signature": signature}))
