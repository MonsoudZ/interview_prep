#!/usr/bin/env python3
"""Trusted published Ruby fixtures only; real candidate execution uses the Linux worker."""
import base64
import json
from pathlib import Path
import re
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[2]
CURRICULUM = Path(__file__).parent

# Intentionally flawed variants derived from each reference; every one must fail at least one group.
MUTATIONS = {
    "merge-intervals": {
        "shrinking_finish": ("[merged.last[1], finish].max", "finish"),
        "touching_not_merged": ("start > merged.last[1]", "start >= merged.last[1]"),
        "mutates_input": ("intervals.sort_by", "intervals.sort_by!"),
        "no_sort": ("intervals.sort_by { |start, finish| [start, finish] }", "intervals"),
    },
    "lru-cache": {
        "get_without_refresh": ("value = @entries.delete(key)\n    @entries[key] = value", "@entries[key]"),
        "evicts_one_early": ("> @capacity", ">= @capacity"),
        "replace_does_not_refresh": ("    @entries.delete(key)\n    @entries[key] = value\n    @entries.shift", "    @entries[key] = value\n    @entries.shift"),
    },
    "rate-limiter": {
        "boundary_inclusive": (">= @window", "> @window"),
        "records_rejections": ("return false if stamps.size >= @limit\n    stamps << now", "stamps << now\n    return false if stamps.size > @limit"),
        "shared_log": ("@log[key]", "@log[:shared]"),
    },
    "build-order": {
        "no_tie_break": ("break if @items[parent] <= @items[child]", "break"),
        "no_cycle_check": ("  raise CycleError", "  nil if false # raise CycleError"),
        "self_dependency_allowed": ("    raise ArgumentError, \"#{after.inspect} depends on itself\" if before == after\n", ""),
    },
}


def run(slug, source, prepare=False):
    with tempfile.TemporaryDirectory(prefix="interview-ruby-fixture-") as directory:
        path = Path(directory)
        workspace = path / "workspace"
        workspace.mkdir()
        script = (ROOT / "services/execution_worker/image/ruby.rb").read_text()
        script = script.replace('WORKSPACE = "/workspace"', f"WORKSPACE = {json.dumps(str(workspace))}").replace('RUBY_ROOT = "/opt/ruby"', f"RUBY_ROOT = {json.dumps(str(CURRICULUM))}")
        (path / "run.rb").write_text(script)
        payload = {"files": {"solution.rb": base64.b64encode(source.encode()).decode()}}
        return subprocess.run(["ruby", str(path / "run.rb"), "--exercise", slug] + (["--prepare"] if prepare else []),
                              input=json.dumps(payload), text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, cwd=workspace, timeout=120)


report = []
for slug in sorted(MUTATIONS):
    exercise = CURRICULUM / slug
    test_count = json.loads((exercise / "exercise.json").read_text())["test_count"] if (exercise / "exercise.json").exists() else 12
    reference = (exercise / "reference/solution.rb").read_text()
    variants = {"starter": ((exercise / "starter/solution.rb").read_text(), False), "reference": (reference, True)}
    for label, (old, new) in MUTATIONS[slug].items():
        assert reference.count(old) == 1, f"{slug}: mutation {label} no longer matches the reference"
        variants[label] = (reference.replace(old, new), False)
    for label, (source, successful) in variants.items():
        result = run(slug, source)
        summary = re.search(rf"{test_count} runs, \d+ assertions, \d+ failures, \d+ errors, 0 skips", result.stdout)
        if not summary or (result.returncode == 0) != successful:
            print(result.stdout)
            raise RuntimeError(f"{slug}: {label}")
        report.append(dict(exercise=slug, variant=label, summary=summary[0]))
        print(json.dumps(report[-1]), flush=True)
    for label, source, successful in [("syntax_only", 'raise "must never execute during preparation"\n', True), ("syntax_error", "def broken(", False)]:
        result = run(slug, source, prepare=True)
        assert (result.returncode == 0) == successful, result.stdout
        report.append(dict(exercise=slug, variant=label, preparation_succeeded=successful))
(CURRICULUM / "validation.json").write_text(json.dumps(report, indent=2) + "\n")
