class ExecutionEvidence
  # Exercises published before manifests carried a test count.
  BUILT_IN_TEST_COUNTS = { ["repository-events", 1] => 12, ["merge-intervals", 2] => 12 }.freeze

  # The number of test groups the published runner executes, or nil when the exercise
  # has no runner. A summary is only reported when the runner's count matches it.
  def self.expected_tests(exercise)
    RailsCurriculum.find(exercise.slug, exercise.version)&.fetch("test_count", nil) ||
      BUILT_IN_TEST_COUNTS[[exercise.slug, exercise.version]]
  end

  # This is a summary of in-process output, never an authoritative grade.
  # The candidate can influence that output, so the provenance stays explicit.
  def self.summary(execution, exercise: nil)
    return nil unless execution.purpose == "tests" && %w[execution_completed execution_failed].include?(execution.status)
    expected = expected_tests(exercise || execution.interview_session.exercise_version)
    return nil unless expected
    output = execution.result&.fetch("output", nil).to_s
    match = output.scan(/(\d{1,6}) runs, (\d{1,9}) assertions, (\d{1,6}) failures, (\d{1,6}) errors, (\d{1,6}) skips/).last
    return nil unless match
    tests, assertions, failures, errors, skipped = match.map(&:to_i)
    return nil unless tests == expected && failures + errors + skipped <= tests
    { reported: true, tests: tests, assertions: assertions, failures: failures, errors: errors,
      skipped: skipped, passed: tests - failures - errors - skipped }
  end
end
