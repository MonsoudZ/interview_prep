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
    # Process criteria with a follow-up answer in the packet are expected at target like source criteria,
    # unless the planted defect is in that answer; those without an answer must stay not_observed.
    answered = expect.get('answered_process_criteria', [])
    expected_at_target = list(expect['source_criteria']) + answered
    result = {}
    if defect:
        criterion = ratings.get(defect['criterion'], {})
        result['missed_defect'] = criterion.get('rating') not in BELOW_TARGET
        cited = cites(criterion.get('evidence', []), defect['path'], defect['line']) or any(
            cites(f.get('evidence', []), defect['path'], defect['line']) for f in report.get('findings', []))
        result['defect_uncited'] = not cited
        independent = [c for c in expected_at_target if c != defect['criterion']]
        result['leaked_criteria'] = [c for c in independent if ratings.get(c, {}).get('rating') in BELOW_TARGET]
    else:
        result['unsupported_downgrades'] = [c for c in expected_at_target if ratings.get(c, {}).get('rating') in BELOW_TARGET]
        result['unsupported_major_findings'] = [f.get('title') for f in report.get('findings', []) if f.get('severity') == 'major']
    result['process_criteria_rated'] = [c for c in expect['process_criteria'] if ratings.get(c, {}).get('rating') != 'not_observed']
    if answered:
        result['answered_process_unrated'] = [c for c in answered if ratings.get(c, {}).get('rating', 'not_observed') == 'not_observed']
    result['execution_observations_without_runs'] = [f.get('title') for f in report.get('findings', []) if f.get('category') == 'execution_observation']
    result['clean'] = not any(v for k, v in result.items() if k != 'clean')
    return result

SUMMARY_KEYS = ('case', 'attempt', 'contract_valid', 'semantic', 'usage', 'error')

def attempt_summary(record):
    return {key: record[key] for key in SUMMARY_KEYS if key in record}

def attempt_path(output, case_name, attempt, repeats):
    """A single run keeps `case.json`; repeated runs number each attempt `case.1.json`, `case.2.json`, ..."""
    return output/(case_name + ('.json' if repeats == 1 else '.%d.json' % attempt))

def attempt_paths(output, case_name):
    """Existing attempt files for a case, in attempt order, whichever naming a previous run used."""
    single = output/(case_name + '.json')
    if single.exists(): return [single]
    numbered = [(int(path.suffixes[-2][1:]), path) for path in output.glob(case_name + '.*.json') if path.suffixes[-2][1:].isdigit()]
    return [path for _, path in sorted(numbered)]

def aggregate(case_name, attempts):
    """Agreement across repeated attempts: counts only, never a percentage (see evaluation/README.md).

    Each flag counts the attempts in which it was set (a non-empty list or True); an invalid attempt counts as
    neither clean nor flagged, so clean + flagged attempts can total less than the attempts run."""
    flags = {}
    for attempt in attempts:
        for key, value in attempt.get('semantic', {}).items():
            if key != 'clean' and value: flags[key] = flags.get(key, 0) + 1
    return {'case': case_name, 'attempts': len(attempts),
            'clean_attempts': sum(1 for a in attempts if a.get('contract_valid') and a.get('semantic', {}).get('clean')),
            'invalid_attempts': sum(1 for a in attempts if not a.get('contract_valid')),
            'flag_attempts': dict(sorted(flags.items())),
            'results': attempts}

def passed(results):
    return all(r['contract_valid'] and r.get('semantic', {}).get('clean') for r in results if 'results' not in r) and \
        all(r['clean_attempts'] == r['attempts'] for r in results if 'results' in r)

def write_summary(output, results):
    (output/'summary.json').write_text(json.dumps(results, indent=2))
    return 0 if passed(results) else 1

def rescore(output, packets):
    results = []
    for case in packets:
        attempts = []
        for path in attempt_paths(output, case['case']):
            record = json.loads(path.read_text())
            if record.get('report'): record['semantic'] = semantic_check(record['report'], case['expect'])
            path.write_text(json.dumps(record, indent=2))
            attempts.append(attempt_summary(record))
        if not attempts: continue
        summary = attempts[0] if len(attempts) == 1 and 'attempt' not in attempts[0] else aggregate(case['case'], attempts)
        results.append(summary)
        print(json.dumps(summary), flush=True)
    return write_summary(output, results)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', default='qwen3.5:27b')
    parser.add_argument('--output', required=True, type=Path, help='New output directory; refuses overwrite')
    parser.add_argument('--case', action='append', help='Only run this named case; repeatable')
    parser.add_argument('--thinking', action='store_true', help='Evaluate reasoning mode without changing production settings')
    parser.add_argument('--rescore', action='store_true', help='Re-apply the semantic checks to the existing reports in --output without inference')
    parser.add_argument('--repeats', type=int, default=1, help='Review each case this many times and record per-case agreement in summary.json')
    args = parser.parse_args()
    if args.repeats < 1: parser.error('--repeats must be at least 1')
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
        attempts = []
        for attempt in range(1, args.repeats + 1):
            print('Reviewing ' + case['case'] + (' (attempt %d of %d)' % (attempt, args.repeats) if args.repeats > 1 else ''), flush=True)
            record = {**case, 'model': args.model, 'model_digest': digest, 'prompt_version': PROMPT_VERSION,
                      'prompt_digest': 'sha256:' + hashlib.sha256(PROMPT.encode()).hexdigest(), 'thinking': args.thinking}
            if args.repeats > 1: record['attempt'] = attempt
            path = attempt_path(args.output, case['case'], attempt, args.repeats)
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
            attempts.append(attempt_summary(record))
            if args.repeats > 1: print(json.dumps(attempts[-1]), flush=True)
        summary = attempts[0] if args.repeats == 1 else aggregate(case['case'], attempts)
        results.append(summary)
        print(json.dumps(summary), flush=True)
        write_summary(args.output, results)
    print('Semantic flags cover only the planted expectations. Read the reports against evaluation/README.md.', flush=True)
    return write_summary(args.output, results)

if __name__ == '__main__':
    raise SystemExit(main())
