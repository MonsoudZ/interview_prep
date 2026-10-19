"""Versioned execution boundary. No arbitrary host paths or commands in jobs."""
import base64
import hashlib
import hmac
import json
from pathlib import PurePosixPath
import re
import time
import uuid

MAX_JOB_BYTES = 2 * 1024 * 1024
MAX_SOURCE_BYTES = 1024 * 1024
MAX_FILES = 128
MAX_LIFETIME_SECONDS = 180
OPERATIONS = {"rails.events.v1": ["ruby", "/opt/runner/run.rb"],
              "rails.events.prepare.v1": ["ruby", "/opt/runner/run.rb", "--prepare"]}

for scenario in ("tenant-projects", "idempotent-checkout", "delivery-retries", "activity-feed", "support-escalations", "invoice-amendments", "safe-backfill"):
    OPERATIONS[f"rails.{scenario}.v1"] = ["ruby", "/opt/runner/run.rb", "--exercise", scenario]
    OPERATIONS[f"rails.{scenario}.prepare.v1"] = ["ruby", "/opt/runner/run.rb", "--exercise", scenario, "--prepare"]

OPERATIONS["ruby.intervals.v1"] = ["ruby", "/opt/runner/ruby.rb"]
OPERATIONS["ruby.intervals.prepare.v1"] = ["ruby", "/opt/runner/ruby.rb", "--prepare"]

# Ruby exercises published with a curriculum manifest; images labelled rails-ruby-v3 carry them.
RUBY_SCENARIOS = ("lru-cache", "rate-limiter", "build-order")
for scenario in RUBY_SCENARIOS:
    OPERATIONS[f"ruby.{scenario}.v1"] = ["ruby", "/opt/runner/ruby.rb", "--exercise", scenario]
    OPERATIONS[f"ruby.{scenario}.prepare.v1"] = ["ruby", "/opt/runner/ruby.rb", "--exercise", scenario, "--prepare"]


class ContractError(ValueError):
    pass


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()


def revision(files):
    hashes = {name: hashlib.sha256(base64.b64decode(content, validate=True)).hexdigest()
              for name, content in files.items()}
    return hashlib.sha256(canonical(hashes)).hexdigest()


def allowed_path(name):
    if not isinstance(name, str) or not name or len(name) > 240:
        return False
    path = PurePosixPath(name)
    if path.is_absolute() or str(path) != name or any(p in (".", "..") for p in path.parts):
        return False
    if not re.fullmatch(r"[A-Za-z0-9_./-]+", name):
        return False
    return (name.startswith("app/") and name.endswith(".rb")) or name in ("config/routes.rb", "db/schema.rb")


def validate(payload, now=None):
    now = time.time() if now is None else now
    fields = {"version", "job_id", "tenant_id", "session_id", "exercise", "issued_at",
              "expires_at", "timeout_seconds", "source_revision", "files"}
    if not isinstance(payload, dict) or set(payload) != fields or type(payload["version"]) is not int or payload["version"] != 1:
        raise ContractError("Unknown or incomplete execution contract")
    for field in ("job_id", "tenant_id", "session_id"):
        try:
            if str(uuid.UUID(payload[field])) != payload[field]:
                raise ValueError()
        except (ValueError, TypeError, AttributeError):
            raise ContractError(f"{field} must be a canonical UUID")
    if not isinstance(payload["exercise"], str) or payload["exercise"] not in OPERATIONS:
        raise ContractError("Exercise is not installed on this worker")
    for field in ("issued_at", "expires_at", "timeout_seconds"):
        if type(payload[field]) is not int:
            raise ContractError(f"{field} must be an integer")
    if not 1 <= payload["timeout_seconds"] <= MAX_LIFETIME_SECONDS:
        raise ContractError("Execution timeout exceeds worker policy")
    if payload["issued_at"] > now + 30 or payload["expires_at"] <= now:
        raise ContractError("Job is expired or not yet valid")
    if not 0 < payload["expires_at"] - payload["issued_at"] <= 300:
        raise ContractError("Job validity window exceeds five minutes")
    files = payload["files"]
    if not isinstance(files, dict) or not 1 <= len(files) <= MAX_FILES:
        raise ContractError("Invalid source file count")
    if payload["exercise"].startswith("ruby.") and set(files) != {"solution.rb"}:
        raise ContractError("Ruby accepts only solution.rb")
    total = 0
    for name, content in files.items():
        permitted = name == "solution.rb" if payload["exercise"].startswith("ruby.") else allowed_path(name)
        if not permitted or not isinstance(content, str):
            raise ContractError("Invalid or disallowed source path/content")
        try:
            decoded = base64.b64decode(content, validate=True)
            decoded.decode("utf-8")
        except (ValueError, UnicodeError):
            raise ContractError("Source must be base64-encoded UTF-8")
        total += len(decoded)
    if total > MAX_SOURCE_BYTES:
        raise ContractError("Source exceeds worker policy")
    if payload["source_revision"] != revision(files):
        raise ContractError("Source revision does not match file contents")
    return payload


def verify(envelope, secret):
    if not isinstance(envelope, dict) or set(envelope) != {"payload", "signature"}:
        raise ContractError("Expected signed job envelope")
    if len(secret.encode()) < 32:
        raise ContractError("Signing secret must contain at least 32 bytes")
    signature = envelope["signature"]
    expected = hmac.new(secret.encode(), canonical(envelope["payload"]), hashlib.sha256).hexdigest()
    if not isinstance(signature, str) or not re.fullmatch(r"[0-9a-f]{64}", signature) or not hmac.compare_digest(expected, signature):
        raise ContractError("Invalid job signature")
    return validate(envelope["payload"])
