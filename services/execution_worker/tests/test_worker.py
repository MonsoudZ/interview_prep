import base64
import copy
import hashlib
import hmac
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
import uuid
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from contracts import ContractError, allowed_path, canonical, revision, validate, verify
from worker import InfrastructureError, OUTPUT_LIMIT, Receipts, command_for, execute, preflight, reap


def job():
    files = {"app/controllers/events_controller.rb": base64.b64encode(b"# candidate code\n").decode()}
    now = int(time.time())
    return {"version": 1, "job_id": str(uuid.uuid4()), "tenant_id": str(uuid.uuid4()),
            "session_id": str(uuid.uuid4()), "exercise": "rails.events.v1", "issued_at": now,
            "expires_at": now + 300, "timeout_seconds": 1, "source_revision": revision(files), "files": files}


class ContractTests(unittest.TestCase):
    def test_signed_valid_job_and_tampering(self):
        payload = job()
        secret = "a" * 32
        envelope = {"payload": payload, "signature": hmac.new(secret.encode(), canonical(payload), hashlib.sha256).hexdigest()}
        self.assertEqual(payload, verify(envelope, secret))
        envelope["payload"]["tenant_id"] = str(uuid.uuid4())
        with self.assertRaises(ContractError):
            verify(envelope, secret)

    def test_ruby_dispatch_accepts_only_solution_and_rails_rejects_it(self):
        payload = job()
        payload["exercise"] = "ruby.intervals.v1"
        payload["files"] = {"solution.rb": base64.b64encode(b"def merge_intervals(x); []; end").decode()}
        payload["source_revision"] = revision(payload["files"])
        self.assertEqual(payload, validate(payload))
        self.assertIn("/opt/runner/ruby.rb", command_for(payload, "sha256:" + "a" * 64))
        for exercise, files in [("rails.events.v1", payload["files"]),
                                 ("ruby.intervals.v1", {"app/x.rb": base64.b64encode(b"x").decode()})]:
            changed = dict(payload, exercise=exercise, files=files, source_revision=revision(files))
            with self.subTest(exercise=exercise), self.assertRaises(ContractError):
                validate(changed)

    def test_rails_scenarios_dispatch_to_fixed_trusted_arguments(self):
        for scenario in ("tenant-projects", "idempotent-checkout", "delivery-retries", "activity-feed", "support-escalations", "invoice-amendments", "safe-backfill"):
            for prepare in (False, True):
                payload = job()
                payload["exercise"] = f"rails.{scenario}." + ("prepare.v1" if prepare else "v1")
                command = command_for(payload, "sha256:" + "a" * 64)
                self.assertIn("--exercise", command)
                self.assertIn(scenario, command)
                self.assertEqual(prepare, "--prepare" in command)

    def test_revision_detects_changed_content(self):
        payload = job()
        payload["files"]["app/controllers/events_controller.rb"] = base64.b64encode(b"changed").decode()
        with self.assertRaises(ContractError):
            validate(payload)

    def test_rejects_escape_normalization_and_protected_paths(self):
        for name in ["../Gemfile", "/etc/passwd", "app/../Gemfile", "app//model.rb", "app/./x.rb",
                     "test/integration/events_test.rb", "Gemfile", "app/x.rb\n", "app/evil.rb;id"]:
            with self.subTest(name=name):
                self.assertFalse(allowed_path(name))
        self.assertTrue(allowed_path("app/models/event.rb"))

    def test_expired_future_or_long_jobs(self):
        for update in [{"expires_at": 0}, {"issued_at": int(time.time()) + 100},
                       {"timeout_seconds": 181}, {"timeout_seconds": True}, {"version": True},
                       {"expires_at": int(time.time()) + 1000}]:
            with self.subTest(update=update), self.assertRaises(ContractError):
                validate(dict(job(), **update))

    def test_rejects_commands_images_and_unknown_exercises(self):
        for update in [{"command": "sh"}, {"image": "user/image"}, {"exercise": "shell"}, {"exercise": []}]:
            with self.subTest(update=update), self.assertRaises(ContractError):
                validate(dict(job(), **update))

    def test_rejects_invalid_encoding_and_size(self):
        for files in [{"app/x.rb": "%%%"}, {"app/x.rb": base64.b64encode(b"\xff").decode()},
                      {"app/x.rb": base64.b64encode(b"x" * (1024 * 1024 + 1)).decode()}]:
            payload = job()
            payload["files"] = files
            with self.subTest(size=len(next(iter(files.values())))), self.assertRaises(ContractError):
                validate(payload)

    def test_claim_is_durable_and_rejects_replay(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "receipts.sqlite3"
            first, second = Receipts(path), Receipts(path)
            identity = str(uuid.uuid4())
            first.claim(identity)
            first.complete(identity, {"status": "execution_completed"})
            with self.assertRaises(ContractError):
                second.claim(identity)


class RuntimePolicyTests(unittest.TestCase):
    image = "sha256:" + "a" * 64

    def test_plan_requires_hardened_runtime_and_no_mounts_or_ports(self):
        command = command_for(job(), self.image)
        for flag in ["--runtime=runsc", "--network=none", "--read-only", "--user=1000:1000",
                     "--cap-drop=ALL", "--security-opt=no-new-privileges=true", "--pull=never",
                     "--memory=2g", "--pids-limit=128", "--log-driver=none"]:
            self.assertIn(flag, command)
        for forbidden in ["--privileged", "--volume", "-v", "--mount", "--publish", "-p"]:
            self.assertNotIn(forbidden, command)

    def test_only_immutable_local_image_ids(self):
        for image in ["ruby:latest", "ruby:4.0.1", "--privileged", "sha256:bad"]:
            with self.subTest(image=image), self.assertRaises(ContractError):
                command_for(job(), image)

    def test_missing_runsc_does_not_fall_back(self):
        result = subprocess.CompletedProcess([], 0, stdout=b'{"Runtimes":{"runc":{}}}', stderr=b'')
        with patch("worker.sys.platform", "linux"), patch("worker.subprocess.run", return_value=result):
            with self.assertRaises(InfrastructureError):
                preflight("docker")

    def test_runtime_alias_and_unsupported_limits_fail_closed(self):
        valid = {"Runtimes": {"runsc": {"path": "/usr/local/bin/runsc"}}, "OSType": "linux",
                 "MemoryLimit": True, "PidsLimit": True, "CpuCfsQuota": True}
        invalid = [dict(valid, Runtimes={"runsc": {"path": "runc"}}), dict(valid, MemoryLimit=False),
                   dict(valid, PidsLimit=False), dict(valid, CpuCfsQuota=False), dict(valid, OSType="windows")]
        for info in invalid:
            result = subprocess.CompletedProcess([], 0, stdout=json.dumps(info).encode())
            with self.subTest(info=info), patch("worker.sys.platform", "linux"), patch("worker.subprocess.run", return_value=result):
                with self.assertRaises(InfrastructureError):
                    preflight("docker")
        result = subprocess.CompletedProcess([], 0, stdout=json.dumps(valid).encode())
        with patch("worker.sys.platform", "linux"), patch("worker.subprocess.run", return_value=result):
            self.assertEqual("linux", preflight("docker")["OSType"])

    def test_watchdog_only_removes_expired_owned_containers(self):
        identity = str(uuid.uuid4())
        data = {"Name": "/interview-" + identity, "Config": {"Labels": {
            "interview.worker": "execution-v1", "interview.job": identity, "interview.expires-at": "100"}}}
        responses = [subprocess.CompletedProcess([], 0, stdout=b"abcdef012345\n"),
                     subprocess.CompletedProcess([], 0, stdout=json.dumps([data]).encode())]
        with patch("worker.subprocess.run", side_effect=responses), patch("worker.remove_container") as remove:
            self.assertEqual(["interview-" + identity], reap("docker", now=101))
            remove.assert_called_once_with("docker", "interview-" + identity)

    def test_watchdog_rejects_ownership_mismatch(self):
        data = {"Name": "/unrelated", "Config": {"Labels": {"interview.worker": "execution-v1"}}}
        responses = [subprocess.CompletedProcess([], 0, stdout=b"abcdef012345\n"),
                     subprocess.CompletedProcess([], 0, stdout=json.dumps([data]).encode())]
        with patch("worker.subprocess.run", side_effect=responses), patch("worker.remove_container") as remove:
            with self.assertRaises(InfrastructureError):
                reap("docker", now=101)
            remove.assert_not_called()

    def fake_docker(self, directory, body):
        path = Path(directory) / "fake-docker"
        path.write_text("#!" + sys.executable + "\nimport sys, time\nif sys.argv[1] != 'run':\n sys.exit(0)\n" + body)
        path.chmod(0o700)
        return str(path)

    def test_process_timeout_is_explicit_and_cleanup_invoked(self):
        with tempfile.TemporaryDirectory() as directory:
            docker = self.fake_docker(directory, "time.sleep(10)\n")
            # Local fake process tests orchestration, NOT Docker/gVisor isolation.
            with patch("worker.remove_container") as cleanup:
                result = execute(job(), self.image, docker)
            self.assertEqual("timed_out", result["status"])
            self.assertGreaterEqual(cleanup.call_count, 1)

    def test_output_is_bounded_and_execution_stopped(self):
        with tempfile.TemporaryDirectory() as directory:
            docker = self.fake_docker(directory, "sys.stdout.buffer.write(b'x' * 400000); sys.stdout.flush()\n")
            with patch("worker.remove_container"):
                result = execute(job(), self.image, docker)
            self.assertEqual("output_limit", result["status"])
            self.assertEqual(OUTPUT_LIMIT, len(result["output"]))
            self.assertTrue(result["output_truncated"])

    def test_cleanup_failure_overrides_success(self):
        with tempfile.TemporaryDirectory() as directory:
            docker = self.fake_docker(directory, "sys.stdin.buffer.read(); print('finished')\n")
            with patch("worker.remove_container", side_effect=InfrastructureError("cleanup failed")):
                result = execute(job(), self.image, docker)
            self.assertEqual("infrastructure_error", result["status"])
            self.assertIsNotNone(result["cleanup_error"])


if __name__ == "__main__":
    unittest.main()
