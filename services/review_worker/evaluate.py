#!/usr/bin/env python3
"""Opt-in real Ollama checks using repository examples; never writes practice records."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from provider import Ollama, PROMPT, PROMPT_VERSION

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).parent

BELOW_TARGET = {'needs_development', 'approaching_target'}

def cites(items, path, line):
    return any(e.get('path') == path and e.get('start_line', 0) <= line <= e.get('end_line', 0) for e in items)

def semantic_check(report, expect):
    """Author-specified expectations; each flag is a separate failure mode, never a combined score."""
    ratings = {c['id']: c for c in report.get('criteria', [])}
    defect = expect.get('defect')
    result = {}
    if defect:
        criterion = ratings.get(defect['criterion'], {})
        result['missed_defect'] = criterion.get('rating') not in BELOW_TARGET
        cited = cites(criterion.get('evidence', []), defect['path'], defect['line']) or any(
            cites(f.get('evidence', []), defect['path'], defect['line']) for f in report.get('findings', []))
        result['defect_uncited'] = not cited
        independent = [c for c in expect['source_criteria'] if c != defect['criterion']]
        result['leaked_criteria'] = [c for c in independent if ratings.get(c, {}).get('rating') in BELOW_TARGET]
    else:
        result['unsupported_downgrades'] = [c for c in expect['source_criteria'] if ratings.get(c, {}).get('rating') in BELOW_TARGET]
        result['unsupported_major_findings'] = [f.get('title') for f in report.get('findings', []) if f.get('severity') == 'major']
    result['process_criteria_rated'] = [c for c in expect['process_criteria'] if ratings.get(c, {}).get('rating') != 'not_observed']
    result['execution_observations_without_runs'] = [f.get('title') for f in report.get('findings', []) if f.get('category') == 'execution_observation']
    result['clean'] = not any(v for k, v in result.items() if k != 'clean')
    return result

def rescore(output, packets):
    results = []
    for case in packets:
        path = output/(case['case'] + '.json')
        if not path.exists(): continue
        record = json.loads(path.read_text())
        if record.get('report'): record['semantic'] = semantic_check(record['report'], case['expect'])
        path.write_text(json.dumps(record, indent=2))
        summary = {key: record[key] for key in ('case', 'contract_valid', 'semantic', 'usage', 'error') if key in record}
        results.append(summary)
        print(json.dumps(summary), flush=True)
    (output/'summary.json').write_text(json.dumps(results, indent=2))
    return 0 if all(result['contract_valid'] and result.get('semantic', {}).get('clean') for result in results) else 1

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', default='qwen3.5:27b')
    parser.add_argument('--output', required=True, type=Path, help='New output directory; refuses overwrite')
    parser.add_argument('--case', action='append', help='Only run this named case; repeatable')
    parser.add_argument('--thinking', action='store_true', help='Evaluate reasoning mode without changing production settings')
    parser.add_argument('--rescore', action='store_true', help='Re-apply the semantic checks to the existing reports in --output without inference')
    args = parser.parse_args()
    packets = json.loads(subprocess.check_output(['ruby', str(HERE/'evaluation/build_packets.rb')], cwd=ROOT, text=True))
    if args.case:
        unknown = set(args.case) - {case['case'] for case in packets}
        if unknown: parser.error('Unknown cases: ' + ', '.join(sorted(unknown)))
        packets = [case for case in packets if case['case'] in args.case]
    if args.rescore:
        return rescore(args.output, packets)
    args.output.mkdir(parents=True, exist_ok=False)
    model = Ollama('http://127.0.0.1:11434', args.model, thinking=args.thinking)
    digest = model.digest()
    results = []
    for case in packets:
        print('Reviewing ' + case['case'], flush=True)
        record = {**case, 'model': args.model, 'model_digest': digest, 'prompt_version': PROMPT_VERSION,
                  'prompt_digest': 'sha256:' + hashlib.sha256(PROMPT.encode()).hexdigest(), 'thinking': args.thinking}
        path = args.output/(case['case'] + '.json')
        try:
            record['report'], record['usage'] = model.review(case['packet'], digest)
            path.write_text(json.dumps(record, indent=2))
            checked = subprocess.run(['ruby', str(HERE/'evaluation/validate_report.rb'), str(path.resolve())],
                                     cwd=ROOT, capture_output=True, text=True)
            record['contract_valid'] = checked.returncode == 0
            if checked.returncode: record['validation_error'] = checked.stderr.splitlines()[0]
            record['semantic'] = semantic_check(record['report'], case['expect'])
        except Exception as error:
            record['contract_valid'] = False
            record['error'] = str(error)
            if getattr(error, 'detail', None): record['error_detail'] = error.detail
        path.write_text(json.dumps(record, indent=2))
        summary = {key: record[key] for key in ('case', 'contract_valid', 'semantic', 'usage', 'error') if key in record}
        results.append(summary)
        print(json.dumps(summary), flush=True)
    (args.output/'summary.json').write_text(json.dumps(results, indent=2))
    print('Semantic flags cover only the planted expectations. Read the reports against evaluation/README.md.', flush=True)
    return 0 if all(result['contract_valid'] and result.get('semantic', {}).get('clean') for result in results) else 1

if __name__ == '__main__':
    raise SystemExit(main())
