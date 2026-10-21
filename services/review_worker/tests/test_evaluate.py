"""Semantic expectation flags must separate missed defects, leakage, and unsupported downgrades."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from evaluate import aggregate, attempt_path, attempt_paths, passed, rescore, semantic_check

def report(ratings, findings=()):
    return {'criteria': [{'id': k, 'rating': v, 'evidence': []} for k, v in ratings.items()], 'findings': list(findings)}

class SemanticCheckTests(unittest.TestCase):
    expect = {'source_criteria': ['correctness', 'complexity'], 'process_criteria': ['verification'],
              'defect': {'criterion': 'correctness', 'path': 'solution.rb', 'line': 10}}

    def test_detected_and_cited_defect_with_independent_criteria_is_clean(self):
        finding = {'severity': 'major', 'category': 'source_concern', 'evidence': [{'path': 'solution.rb', 'start_line': 8, 'end_line': 11}]}
        result = semantic_check(report({'correctness': 'needs_development', 'complexity': 'meets_target', 'verification': 'not_observed'}, [finding]), self.expect)
        self.assertTrue(result['clean'], result)

    def test_missed_defect_leakage_and_misrated_process_criterion_are_separate_flags(self):
        result = semantic_check(report({'correctness': 'meets_target', 'complexity': 'approaching_target', 'verification': 'needs_development'}), self.expect)
        self.assertFalse(result['clean'])
        self.assertTrue(result['missed_defect']); self.assertTrue(result['defect_uncited'])
        self.assertEqual(['complexity'], result['leaked_criteria']); self.assertEqual(['verification'], result['process_criteria_rated'])

    def test_reference_cases_flag_downgrades_major_findings_and_fabricated_execution_observations(self):
        expect = {**self.expect, 'defect': None}
        clean = semantic_check(report({'correctness': 'meets_target', 'complexity': 'meets_target', 'verification': 'not_observed'},
                                      [{'severity': 'minor', 'category': 'refinement', 'title': 'style'}]), expect)
        self.assertTrue(clean['clean'])
        flagged = semantic_check(report({'correctness': 'meets_target', 'complexity': 'approaching_target', 'verification': 'not_observed'},
                                        [{'severity': 'major', 'category': 'execution_observation', 'title': 'missing logs'}]), expect)
        self.assertEqual(['complexity'], flagged['unsupported_downgrades'])
        self.assertEqual(['missing logs'], flagged['unsupported_major_findings'])
        self.assertEqual(['missing logs'], flagged['execution_observations_without_runs'])

def attempt(valid=True, **flags):
    semantic = {'missed_defect': False, 'defect_uncited': False, 'leaked_criteria': [], 'process_criteria_rated': [],
                'execution_observations_without_runs': [], **flags}
    semantic['clean'] = not any(v for k, v in semantic.items() if k != 'clean')
    return {'case': 'x', 'contract_valid': valid, 'semantic': semantic}

class RepeatAggregationTests(unittest.TestCase):
    def test_counts_clean_attempts_and_attempts_per_flag_without_a_score(self):
        summary = aggregate('x', [attempt(), attempt(leaked_criteria=['complexity']), attempt(missed_defect=True, leaked_criteria=['boundaries'])])
        self.assertEqual(3, summary['attempts']); self.assertEqual(1, summary['clean_attempts']); self.assertEqual(0, summary['invalid_attempts'])
        self.assertEqual({'leaked_criteria': 2, 'missed_defect': 1}, summary['flag_attempts'])
        self.assertEqual(3, len(summary['results']))
        self.assertFalse(any(isinstance(v, float) or 'score' in k or 'rate' in k for k, v in summary.items()), summary)

    def test_invalid_or_errored_attempts_are_neither_clean_nor_flagged(self):
        summary = aggregate('x', [attempt(), {'case': 'x', 'contract_valid': False, 'error': 'timeout'}, attempt(valid=False)])
        self.assertEqual(1, summary['clean_attempts']); self.assertEqual(2, summary['invalid_attempts']); self.assertEqual({}, summary['flag_attempts'])

    def test_pass_requires_every_attempt_of_every_case_clean(self):
        self.assertTrue(passed([attempt(), aggregate('y', [attempt(), attempt()])]))
        self.assertFalse(passed([attempt(), aggregate('y', [attempt(), attempt(defect_uncited=True)])]))
        self.assertFalse(passed([attempt(valid=False)]))

    def test_single_run_keeps_unnumbered_file_and_repeats_number_each_attempt(self):
        out = Path('/out')
        self.assertEqual(out/'x.json', attempt_path(out, 'x', 1, 1))
        self.assertEqual([out/'x.1.json', out/'x.2.json'], [attempt_path(out, 'x', n, 2) for n in (1, 2)])

class RescoreRepeatedAttemptsTests(unittest.TestCase):
    expect = {'source_criteria': ['correctness', 'complexity'], 'process_criteria': [],
              'defect': {'criterion': 'correctness', 'path': 'solution.rb', 'line': 10}}

    def write(self, out, name, ratings, **extra):
        (out/name).write_text(json.dumps({'case': 'x', 'contract_valid': True, 'report': report(ratings), **extra}))

    def test_rescore_aggregates_numbered_attempts_in_order_and_keeps_single_runs_flat(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            self.write(out, 'x.10.json', {'correctness': 'meets_target', 'complexity': 'meets_target'}, attempt=10)
            for n in (1, 2): self.write(out, 'x.%d.json' % n, {'correctness': 'needs_development', 'complexity': 'meets_target'}, attempt=n)
            self.write(out, 'y.json', {'correctness': 'meets_target', 'complexity': 'approaching_target'})
            self.assertEqual([out/'x.1.json', out/'x.2.json', out/'x.10.json'], attempt_paths(out, 'x'))
            status = rescore(out, [{'case': 'x', 'expect': self.expect}, {'case': 'y', 'expect': {**self.expect, 'defect': None}}, {'case': 'absent', 'expect': self.expect}])
            x, y = json.loads((out/'summary.json').read_text())
            self.assertEqual(1, status)
            self.assertEqual((3, 0, {'defect_uncited': 3, 'missed_defect': 1}), (x['attempts'], x['clean_attempts'], x['flag_attempts']))
            self.assertEqual([1, 2, 10], [r['attempt'] for r in x['results']])
            self.assertNotIn('results', y); self.assertEqual(['complexity'], y['semantic']['unsupported_downgrades'])
            self.assertTrue(json.loads((out/'x.10.json').read_text())['semantic']['missed_defect'])

if __name__ == '__main__': unittest.main()
