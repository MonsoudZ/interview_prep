"""Semantic expectation flags must separate missed defects, leakage, and unsupported downgrades."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from evaluate import semantic_check

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

if __name__ == '__main__': unittest.main()
