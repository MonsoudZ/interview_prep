class ReviewGatewayController < ActionController::API
  before_action :authenticate_worker
  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "Not found" }, status: :not_found
  end
  ERRORS = %w[model_unavailable context_too_large output_invalid inference_timeout worker_interrupted model_changed].freeze
  LEASE_LENGTH = 6.minutes
  LEASE_HARD_CAP = 20.minutes

  def heartbeat
    id, model, digest = params.values_at(:worker_id, :model, :model_digest)
    unless uuid?(id) && model.is_a?(String) && model.match?(/\A[A-Za-z0-9_.:\/-]{1,100}\z/) && digest.is_a?(String) && digest.match?(/\Asha256:[0-9a-f]{64}\z/)
      return render json: { error: "Invalid worker metadata" }, status: :unprocessable_content
    end
    worker = ReviewWorker.find_or_initialize_by(id: id)
    worker.update!(model: model, model_digest: digest, last_seen_at: Time.current)
    # A heartbeating worker keeps its own running review leased while long reasoning-mode inference continues.
    # update_columns leaves updated_at at the lease time, so the hard cap is measured from when the work started.
    running = AutomatedReview.find_by(worker_id: worker.id, status: "running", model_digest: digest)
    running&.update_columns(lease_expires_at: [LEASE_LENGTH.from_now, running.updated_at + LEASE_HARD_CAP].min)
    render json: { ok: true }
  end

  def lease
    return render json: { error: "Invalid worker identity" }, status: :bad_request unless uuid?(params[:worker_id])
    worker = ReviewWorker.available.find(params[:worker_id])
    AutomatedReviewWorkflow.expire!
    review, token = nil, SecureRandom.hex(32)
    AutomatedReview.transaction do
      worker.lock!
      unless AutomatedReview.exists?(worker_id: worker.id, status: "running")
        lock = ActiveRecord::Base.connection.adapter_name == "PostgreSQL" ? "FOR UPDATE SKIP LOCKED" : true
        candidate = AutomatedReview.where(status: "queued").order(:created_at).lock(lock).first
        if candidate
          candidate.update!(status: "running", worker_id: worker.id, model: worker.model, model_digest: worker.model_digest,
            lease_digest: Digest::SHA256.hexdigest(token), lease_expires_at: LEASE_LENGTH.from_now)
          review = candidate
        end
      end
    end
    render json: review ? { job: { id: review.id, revision: review.source_snapshot.revision, prompt_version: review.prompt_version, input: review.input }, lease_token: token } : { job: nil }
  end

  def result
    review = AutomatedReview.find(params[:id])
    review.with_lock do
      supplied = Digest::SHA256.hexdigest(params[:lease_token].to_s)
      unless review.lease_digest && ActiveSupport::SecurityUtils.secure_compare(review.lease_digest, supplied)
        return render json: { error: "Invalid lease" }, status: :unauthorized
      end
      return render json: { ok: true } if %w[completed failed].include?(review.status)
      if review.status != "running" || review.lease_expires_at <= Time.current
        return render json: { error: "Lease expired" }, status: :conflict
      end
      unless params[:revision] == review.source_snapshot.revision && params[:model] == review.model && params[:model_digest] == review.model_digest && params[:prompt_version] == review.prompt_version
        return render json: { error: "Result identity mismatch" }, status: :conflict
      end
      if params[:status] == "failed" && ERRORS.include?(params[:error_code])
        review.update!(status: "failed", error_code: params[:error_code])
      elsif params[:status] == "completed"
        value = params[:report]
        value = value.to_unsafe_h if value.is_a?(ActionController::Parameters)
        begin
          report = AutomatedReviewReport.check!(value, review.input)
          usage = params[:usage].is_a?(ActionController::Parameters) ? params[:usage].permit(:input_tokens, :output_tokens, :duration_seconds, :reasoning).to_h : {}
          unless usage.values.all? { |number| number.is_a?(Numeric) && number.finite? && number.between?(0, 1_000_000_000) }
            raise Workspace::Invalid, "Invalid usage"
          end
          review.update!(status: "completed", report: report, usage: usage)
        rescue Workspace::Invalid
          review.update!(status: "failed", report: nil, error_code: "output_invalid")
        end
      else
        return render json: { error: "Invalid result status" }, status: :unprocessable_content
      end
    end
    render json: { ok: true }
  end

  private
  def uuid?(value) = value.is_a?(String) && value.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
  def authenticate_worker
    secret = ENV["INTERVIEW_REVIEW_BRIDGE_KEY"].to_s
    supplied = request.headers["Authorization"].to_s.delete_prefix("Bearer ")
    unless secret.bytesize >= 32 && ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(secret), Digest::SHA256.hexdigest(supplied))
      render json: { error: "Review worker authentication required" }, status: :unauthorized
    end
  end
end
