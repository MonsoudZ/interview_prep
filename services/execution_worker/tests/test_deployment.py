import json
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_image import ROOT, build_command
from doctor import diagnose
from worker import InfrastructureError, inspect_image


class DeploymentTests(unittest.TestCase):
    image = "sha256:" + "a" * 64

    def test_build_requires_pinned_official_base(self):
        for base in ["ruby:latest", "ruby:4.0.1-slim", "evil.example/ruby@sha256:" + "a" * 64]:
            with self.subTest(base=base), self.assertRaises(ValueError):
                build_command("docker", base)
        command = build_command("docker", "ruby@sha256:" + "b" * 64)
        self.assertIn("--iidfile", command)
        self.assertEqual(str(ROOT), command[-1])

    def test_linux_dependency_lock_matches_template_and_has_checksums(self):
        dependencies = ROOT / "services/execution_worker/image/dependencies"
        self.assertEqual((ROOT / "experiments/rails-runtime/template/Gemfile").read_text(), (dependencies / "Gemfile").read_text())
        lock = (dependencies / "Gemfile.lock").read_text()
        platforms = lock.split("PLATFORMS\n")[1].split("\n\n")[0]
        self.assertEqual("  ruby", platforms)
        checksums = lock.split("CHECKSUMS\n")[1].split("\n\n")[0].splitlines()
        self.assertGreater(len(checksums), 50)
        self.assertTrue(all(" sha256=" in line for line in checksums))

    def image_info(self):
        return {"Id": self.image, "Os": "linux", "Architecture": "arm64", "Config": {
            "User": "1000:1000", "Labels": {"interview.contract": "1", "interview.exercise": "rails.events.v1"}}}

    def test_image_checks_id_os_labels_and_user(self):
        valid = self.image_info()
        result = subprocess.CompletedProcess([], 0, stdout=json.dumps([valid]).encode())
        with patch("worker.subprocess.run", return_value=result):
            self.assertEqual(self.image, inspect_image("docker", self.image)["Id"])
        for mutation in [{"Id": "wrong"}, {"Os": "windows"}, {"Config": {"User": "root"}}]:
            bad = dict(valid, **mutation)
            result = subprocess.CompletedProcess([], 0, stdout=json.dumps([bad]).encode())
            with self.subTest(mutation=mutation), patch("worker.subprocess.run", return_value=result):
                with self.assertRaises(InfrastructureError):
                    inspect_image("docker", self.image)

    def test_image_inventory_does_not_advertise_exercises_from_newer_images(self):
        for label, expected in [(None, 2), ("rails-v1", 10), ("rails-ruby-v1", 12)]:
            info = self.image_info()
            if label:
                info["Config"]["Labels"]["interview.curriculum"] = label
            result = subprocess.CompletedProcess([], 0, stdout=json.dumps([info]).encode())
            with self.subTest(label=label), patch("worker.subprocess.run", return_value=result):
                self.assertEqual(expected, len(inspect_image("docker", self.image)["operations"]))

    def test_missing_docker_is_not_readiness_success(self):
        with patch("doctor.shutil.which", return_value=None):
            report = diagnose(self.image)
        self.assertFalse(report["ready"])
        self.assertFalse(report["live_execution_tested"])
        self.assertTrue(report["issues"])
