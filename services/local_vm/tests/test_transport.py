import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

path = Path(__file__).resolve().parents[1] / "execute.py"
spec = importlib.util.spec_from_file_location("local_vm_execute", path)
transport = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transport)


class LocalVMTransportTests(unittest.TestCase):
    def test_profile_cannot_inject_ssh_flags_or_shell_commands(self):
        for profile in ("../default", "--help", "interview; id", "a" * 33, ""):
            with self.assertRaises(ValueError):
                transport.command(profile)

    def test_exact_guest_command_has_no_host_execution_fallback(self):
        command = transport.command("interview")
        self.assertEqual(command, ["colima", "-p", "interview", "ssh", "--", "python3", "/opt/interview/services/local_vm/guest.py"])

    def test_keys_use_stdin_only_and_transport_is_bounded(self):
        with patch.object(transport.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, b"{}", b"")) as mocked:
            secret = "s" * 40
            transport.run({"payload": {"job_id": "fixture"}}, secret, "sha256:" + "a" * 64)
            args, kwargs = mocked.call_args
            self.assertNotIn(secret, " ".join(args[0]))
            self.assertEqual(json.loads(kwargs["input"])["signing_key"], secret)
            self.assertEqual(kwargs["timeout"], 100)
            self.assertNotIn("shell", kwargs)

    def test_missing_key_never_starts_a_process(self):
        with patch.object(transport.subprocess, "run") as mocked:
            with self.assertRaises(ValueError):
                transport.run({}, "short", "image")
            mocked.assert_not_called()


if __name__ == "__main__":
    unittest.main()
