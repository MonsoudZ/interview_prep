"""Every published Ruby exercise stages through the trusted dispatcher: starter fails, reference passes."""
import base64
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from contracts import OPERATIONS, RUBY_SCENARIOS

ROOT = Path(__file__).resolve().parents[3]
CURRICULUM = ROOT / "curriculum/ruby"


class RubyContractTests(unittest.TestCase):
    def test_every_ruby_scenario_dispatches_to_fixed_trusted_arguments(self):
        for slug in RUBY_SCENARIOS:
            self.assertEqual(["ruby", "/opt/runner/ruby.rb", "--exercise", slug], OPERATIONS[f"ruby.{slug}.v1"])
            self.assertEqual(["ruby", "/opt/runner/ruby.rb", "--exercise", slug, "--prepare"], OPERATIONS[f"ruby.{slug}.prepare.v1"])
            manifest = json.loads((CURRICULUM / slug / "exercise.json").read_text())
            self.assertEqual(f"ruby.{slug}.v1", manifest["operation"])
            self.assertEqual(12, manifest["test_count"])


@unittest.skipUnless(shutil.which("ruby"), "Ruby is required to stage the trusted exercise fixtures")
class RubyStagingTests(unittest.TestCase):
    def run_entrypoint(self, slug, source, prepare=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workspace = root / "workspace"
            workspace.mkdir()
            script = (ROOT / "services/execution_worker/image/ruby.rb").read_text()
            script = script.replace('WORKSPACE = "/workspace"', f"WORKSPACE = {json.dumps(str(workspace))}").replace('RUBY_ROOT = "/opt/ruby"', f"RUBY_ROOT = {json.dumps(str(CURRICULUM))}")
            (root / "run.rb").write_text(script)
            payload = {"files": {"solution.rb": base64.b64encode(source.encode()).decode()}}
            return subprocess.run([shutil.which("ruby"), str(root / "run.rb"), "--exercise", slug] + (["--prepare"] if prepare else []),
                                  input=json.dumps(payload).encode(), cwd=workspace, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)

    def test_starters_fail_and_references_pass_with_twelve_groups(self):
        for slug in RUBY_SCENARIOS:
            with self.subTest(slug=slug):
                starter = self.run_entrypoint(slug, (CURRICULUM / slug / "starter/solution.rb").read_text())
                self.assertNotEqual(0, starter.returncode)
                self.assertRegex(starter.stdout.decode(errors="replace"), r"12 runs, \d+ assertions, [1-9]\d* failures")
                reference = self.run_entrypoint(slug, (CURRICULUM / slug / "reference/solution.rb").read_text())
                self.assertEqual(0, reference.returncode, reference.stdout.decode(errors="replace"))
                self.assertRegex(reference.stdout.decode(errors="replace"), r"12 runs, \d+ assertions, 0 failures, 0 errors, 0 skips")
                prepared = self.run_entrypoint(slug, 'raise "never executed"\n', prepare=True)
                self.assertEqual(0, prepared.returncode)
                self.assertIn(b"READY:", prepared.stdout)

    def test_unknown_exercise_is_refused_before_staging(self):
        result = self.run_entrypoint("../etc", "x = 1\n")
        self.assertNotEqual(0, result.returncode)
        self.assertIn(b"Unknown exercise", result.stdout)
