class ExecutionEvidence
  # This is a summary of in-process output, never an authoritative grade.
  # The candidate can influence that output, so the provenance stays explicit.
  def self.summary(execution)
    return nil unless execution.purpose == "tests" && %w[execution_completed execution_failed].include?(execution.status)
    output = execution.result&.fetch("output", nil).to_s
    match = output.scan(/(\d{1,6}) runs, (\d{1,9}) assertions, (\d{1,6}) failures, (\d{1,6}) errors, (\d{1,6}) skips/).last
    return nil unless match
    tests, assertions, failures, errors, skipped = match.map(&:to_i)
    return nil unless tests == 12 && failures + errors + skipped <= tests
    { reported: true, tests: tests, assertions: assertions, failures: failures, errors: errors,
      skipped: skipped, passed: tests - failures - errors - skipped }
  end
end
