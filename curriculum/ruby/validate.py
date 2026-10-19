#!/usr/bin/env python3
"""Trusted published Ruby fixtures only; real candidate execution uses the Linux worker."""
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[2]
EXERCISE = Path(__file__).parent / "merge-intervals"

def run(source, prepare=False):
    with tempfile.TemporaryDirectory(prefix="interview-ruby-fixture-") as directory:
        path = Path(directory)
        workspace = path / "workspace"; workspace.mkdir()
        script = (ROOT / "services/execution_worker/image/ruby.rb").read_text()
        script = script.replace('/workspace', str(workspace)).replace('/opt/ruby/merge-intervals', str(EXERCISE))
        (path / "run.rb").write_text(script)
        payload = {"files": {"solution.rb": base64.b64encode(source.encode()).decode()}}
        return subprocess.run(["ruby", str(path / "run.rb")] + (["--prepare"] if prepare else []),
                              input=json.dumps(payload), text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, cwd=workspace, timeout=30)

reference = (EXERCISE / 'reference/solution.rb').read_text()
variants = {
    'starter': ((EXERCISE / 'starter/solution.rb').read_text(), False),
    'reference': (reference, True),
    'shrinking_finish': (reference.replace('[merged.last[1], finish].max', 'finish'), False),
    'touching_not_merged': (reference.replace('start > merged.last[1]', 'start >= merged.last[1]'), False),
    'mutates_input': (reference.replace('intervals.sort_by', 'intervals.sort_by!'), False),
    'no_sort': (reference.replace('intervals.sort_by { |start, finish| [start, finish] }', 'intervals'), False)
}
report = []
for label, (source, successful) in variants.items():
    result = run(source)
    summary = re.search(r'12 runs, \d+ assertions, \d+ failures, \d+ errors, 0 skips', result.stdout)
    if not summary or (result.returncode == 0) != successful:
        print(result.stdout); raise RuntimeError(label)
    report.append(dict(variant=label, summary=summary[0]))
    print(json.dumps(report[-1]), flush=True)
for label, source, successful in [('syntax_only', 'raise "must never execute during preparation"\ndef merge_intervals(intervals); end', True), ('syntax_error', 'def merge_intervals(', False)]:
    result = run(source, prepare=True)
    assert (result.returncode == 0) == successful, result.stdout
    report.append(dict(variant=label, preparation_succeeded=successful))
(Path(__file__).parent / 'validation.json').write_text(json.dumps(report, indent=2)+'\n')
