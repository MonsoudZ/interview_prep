class AutomatedReviewWorkflow
  def self.expire!
    AutomatedReview.where(status: "running").where("lease_expires_at <= ?", Time.current).update_all(status: "failed", error_code: "worker_interrupted", updated_at: Time.current)
    AutomatedReview.where(status: "queued").where("created_at <= ?", 30.minutes.ago).update_all(status: "failed", error_code: "worker_unavailable", updated_at: Time.current)
  end

  def self.request!(session, account, request_id)
    raise SessionCommandError, "Behavioral rehearsal uses self-review; automated feedback is not connected for this track" if session.exercise_version.track == "behavioral"
    unless request_id.is_a?(String) && request_id.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
      raise Workspace::Invalid, "Invalid review request identity"
    end
    expire!
    account.with_lock do
      session.with_lock do
        session.expire_locked!
        raise SessionCommandError, "Submit your work before requesting automated feedback" unless session.status == "submitted"
        existing = session.automated_reviews.find_by(client_request_id: request_id)
        return existing if existing
        existing = session.automated_reviews.where(status: %w[queued running completed]).order(created_at: :desc).first
        return existing if existing
        raise SessionCommandError.new("The Studio review worker is offline. Your submission is preserved; connect it before requesting a review.", status: :service_unavailable) unless ReviewWorker.available.exists?
        pending = AutomatedReview.joins(:interview_session).where(interview_sessions: { account_id: account.id }, status: %w[queued running]).count
        raise SessionCommandError.new("Two reviews are already pending. Wait before requesting another.", status: :too_many_requests) if pending >= 2
        packet = ReviewPacket.build(session)
        session.automated_reviews.create!(client_request_id: request_id, source_snapshot: session.source_snapshots.find_by!(revision: session.submitted_revision),
          prompt_version: ReviewPacket::PROMPT_VERSION, content_version: PracticeContent.for(session.exercise_version).fetch("version"), input: packet)
      end
    end
  end

  def self.present(session)
    return { available: false, supported: false, review: nil, notice: "Behavioral rehearsal uses self-review of the submitted answer; no automated behavioral judgment is available." } if session.exercise_version.track == "behavioral"
    expire!
    review = session.automated_reviews.order(created_at: :desc).first
    worker = ReviewWorker.available.order(last_seen_at: :desc).first
    { available: worker.present?, configured_model: worker&.model,
      review: review && { id: review.id, status: review.status, revision: review.source_snapshot.revision,
        created_at: review.created_at, updated_at: review.updated_at, model: review.model, model_digest: review.model_digest,
        prompt_version: review.prompt_version, content_version: review.content_version,
        report: review.report, error_code: review.error_code, usage: review.usage },
      notice: "Local-model feedback is advisory. Source citations are checked, but judgments may be wrong. This is not a calibrated hiring score." }
  end
end
