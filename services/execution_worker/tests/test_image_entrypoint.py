"""Trusted local integration check of image staging; does not simulate isolation."""
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]


@unittest.skipUnless(shutil.which("ruby"), "Ruby is required for trusted Rails staging integration")
class ImageStagingTests(unittest.TestCase):
    def run_entrypoint(self, reference, prepare=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            template = root / "exercise"
            workspace = root / "workspace"
            workspace.mkdir()
            shutil.copytree(ROOT / "experiments/rails-runtime/template", template)
            # Match read-only image source permissions. Workspace copies must be writable.
            for path in template.rglob("*"):
                if path.is_file():
                    path.chmod(0o444)
            entrypoint = (ROOT / "services/execution_worker/image/run.rb").read_text()
            entrypoint = entrypoint.replace('"/workspace"', json.dumps(str(workspace)))
            entrypoint = entrypoint.replace('"/opt/exercise/*"', json.dumps(str(template / "*")))
            script = root / "run.rb"
            script.write_text(entrypoint)
            source = ROOT / "experiments/rails-runtime" / ("reference" if reference else "template")
            files = {str(path.relative_to(source)): base64.b64encode(path.read_bytes()).decode()
                     for path in (source / "app").rglob("*.rb")}
            env = os.environ.copy()
            env.pop("BUNDLE_GEMFILE", None)
            env["BUNDLE_APP_CONFIG"] = str(root / "bundle-config")
            env["RAILS_ENV"] = "test"
            return subprocess.run([shutil.which("ruby"), str(script)] + (["--prepare"] if prepare else []), input=json.dumps({"files": files}).encode(),
                                  env=env, cwd=workspace, stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, timeout=30)

    def test_readonly_starter_stages_and_has_twelve_failures(self):
        result = self.run_entrypoint(reference=False)
        output = result.stdout.decode(errors="replace")
        self.assertEqual(1, result.returncode, output)
        self.assertRegex(output, r"12 runs, 12 assertions, 12 failures, 0 errors, 0 skips")

    def test_reference_overlays_readonly_template_and_passes(self):
        result = self.run_entrypoint(reference=True)
        output = result.stdout.decode(errors="replace")
        self.assertEqual(0, result.returncode, output)
        self.assertRegex(output, r"12 runs, 158 assertions, 0 failures, 0 errors, 0 skips")

    def test_preparation_does_not_require_candidate_to_pass_tests(self):
        result = self.run_entrypoint(reference=False, prepare=True)
        output = result.stdout.decode(errors="replace")
        self.assertEqual(0, result.returncode, output)
        self.assertIn("READY:", output)
        self.assertNotIn("12 runs", output)
