require "openssl"
require "base64"
class WorkerJobs
  TEST_OPERATIONS = (["rails.events.v1", "ruby.intervals.v1"] + RailsCurriculum.entries.map { |entry| entry.fetch("operation") }).freeze
  def self.prepare_operation(operation)
    operation.sub(/\.v1\z/, ".prepare.v1")
  end
  OPERATIONS = TEST_OPERATIONS.flat_map { |operation| [operation, prepare_operation(operation)] }.freeze

  def self.sorted(value)
    value.is_a?(Hash) ? value.sort.to_h.transform_values { |item| sorted(item) } : value
  end

  def self.envelope(execution)
    secret = ENV.fetch("INTERVIEW_WORKER_SIGNING_KEY")
    raise "Worker signing key must be at least 32 bytes" if secret.bytesize < 32
    session = execution.interview_session
    operation = session.exercise_version.operation
    operation = prepare_operation(operation) if execution.purpose == "prepare"
    now = Time.current.to_i
    files = execution.source_snapshot.files.transform_values { |text| Base64.strict_encode64(text) }
    payload = { version: 1, job_id: execution.id, tenant_id: session.account_id, session_id: session.id,
      exercise: operation, issued_at: now, expires_at: now + 120, timeout_seconds: 60,
      source_revision: execution.source_snapshot.revision, files: files }.stringify_keys
    { payload: payload, signature: OpenSSL::HMAC.hexdigest("SHA256", secret, JSON.generate(sorted(payload))) }
  end

  def self.expire_leases!(scope: ExecutionRequest.all)
    scope.where(status: "leased").where("lease_expires_at <= ?", Time.current).find_each do |request|
      request.with_lock do
        next unless request.status == "leased" && request.lease_expires_at <= Time.current
        request.update!(status: "infrastructure_error", result: { status: "infrastructure_error", output: "Worker lease expired. Run again explicitly." })
        session = request.interview_session
        session.with_lock { session.update!(status: "draft") if request.purpose == "prepare" && session.status == "preparing" }
      end
    end
  end
end
