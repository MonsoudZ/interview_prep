class WorkerGatewayController < ActionController::API
  before_action :authenticate_worker
  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "Not found" }, status: :not_found
  end

  def heartbeat
    worker = worker_identity
    return if performed?
    capabilities = Array(params[:capabilities]) & WorkerJobs::OPERATIONS
    worker.update!(last_seen_at: Time.current, capabilities: capabilities)
    render json: { ok: true }
  end

  def lease
    worker = worker_identity
    return if performed?
    return render json: { error: "Signing key is not configured" }, status: :service_unavailable if ENV["INTERVIEW_WORKER_SIGNING_KEY"].to_s.bytesize < 32
    WorkerJobs.expire_leases!
    execution = nil
    token = SecureRandom.hex(32)
    ExecutionRequest.transaction do
      worker.lock!
      return render json: { job: nil } if ExecutionRequest.exists?(worker_id: worker.id, status: "leased")
      scope = ExecutionRequest.joins(interview_session: :exercise_version).where(status: "queued")
      candidates = scope.where(purpose: "tests", exercise_versions: { operation: worker.capabilities })
      preparable = WorkerJobs::TEST_OPERATIONS.select { |operation| worker.capabilities.include?(WorkerJobs.prepare_operation(operation)) }
      candidates = candidates.or(scope.where(purpose: "prepare", exercise_versions: { operation: preparable }))
      locking = ActiveRecord::Base.connection.adapter_name == "PostgreSQL" ? "FOR UPDATE OF execution_requests SKIP LOCKED" : true
      candidate = candidates.order("execution_requests.created_at").lock(locking).first
      if candidate
        candidate.update!(status: "leased", worker_id: worker.id, lease_digest: Digest::SHA256.hexdigest(token), lease_expires_at: 3.minutes.from_now)
        execution = candidate
      end
    end
    render json: execution ? { job: WorkerJobs.envelope(execution), lease_token: token } : { job: nil }
  end

  def result
    execution = ExecutionRequest.find(params[:id])
    execution.with_lock do
      supplied = Digest::SHA256.hexdigest(params[:lease_token].to_s)
      unless execution.lease_digest && ActiveSupport::SecurityUtils.secure_compare(execution.lease_digest, supplied)
        return render json: { error: "Invalid lease" }, status: :unauthorized
      end
      return render json: { ok: true } unless execution.status == "leased"
      return render json: { error: "Lease expired" }, status: :conflict if execution.lease_expires_at <= Time.current
      body = params.require(:result).permit(:version, :job_id, :tenant_id, :session_id, :source_revision, :status, :exit_code, :duration_seconds, :output, :output_truncated, :cleanup_error, :grading_authority, :runtime_provider).to_h
      session = execution.interview_session
      unless body["job_id"] == execution.id && body["tenant_id"] == session.account_id && body["session_id"] == session.id && body["source_revision"] == execution.source_snapshot.revision
        return render json: { error: "Result identity/revision mismatch" }, status: :conflict
      end
      allowed = %w[execution_completed execution_failed timed_out output_limit infrastructure_error]
      unless body["runtime_provider"].nil? || %w[railway_sandbox docker_gvisor].include?(body["runtime_provider"])
        return render json: { error: "Invalid runtime provider" }, status: :unprocessable_content
      end
      return render json: { error: "Invalid execution status" }, status: :unprocessable_content unless allowed.include?(body["status"])
      unless body["version"] == 1 && (body["exit_code"].nil? || body["exit_code"].is_a?(Integer)) &&
          (body["status"] != "execution_completed" || body["exit_code"] == 0)
        return render json: { error: "Invalid result version or exit code" }, status: :unprocessable_content
      end
      body["output"] = body["output"].to_s.byteslice(0, 262144).to_s.force_encoding("UTF-8").scrub
      execution.update!(status: body["status"], result: body)
      if execution.purpose == "prepare"
        session.with_lock do
          if session.status == "preparing"
            ready = body["status"] == "execution_completed" && body["exit_code"] == 0 && session.current_revision == execution.source_snapshot.revision
            session.update!(status: ready ? "ready" : "draft")
          end
        end
      end
    end
    render json: { ok: true }
  end

  private

  def authenticate_worker
    secret = ENV["INTERVIEW_WORKER_BRIDGE_KEY"].to_s
    provided = request.headers["Authorization"].to_s.delete_prefix("Bearer ")
    unless secret.bytesize >= 32 && ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(secret), Digest::SHA256.hexdigest(provided))
      render json: { error: "Worker authentication required" }, status: :unauthorized
    end
  end

  def worker_identity
    id = params[:worker_id].to_s
    unless id.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
      render json: { error: "Invalid worker identity" }, status: :bad_request
      return
    end
    WorkerNode.find_or_create_by!(id: id) { |worker| worker.last_seen_at = Time.current; worker.capabilities = [] }
  end
end
