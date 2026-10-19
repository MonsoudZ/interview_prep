class SessionReviewsController < ApplicationController
  before_action :require_submission

  def show
    render json: ReviewWorkflow.present(owner_session, @content)
  end

  def reference
    files = RailsCurriculum.reference(owner_session.exercise_version)
    return render json: { error: "No reference is published for this version" }, status: :not_found unless files
    render json: { files: files, note: "One tested implementation, not the only acceptable design. Compare behavior and tradeoffs after reviewing your own submission." }
  end

  def update
    record = owner_session
    record.with_lock do
      review = record.session_review
      unless params.key?(:expected_version) && params[:expected_version] == review&.lock_version
        return render json: { error: "A newer review exists. Reopen the review before saving." }, status: :conflict
      end
      raise ActionController::ParameterMissing, :entries unless params.key?(:entries)
      entries = params[:entries]
      entries = entries.to_unsafe_h if entries.is_a?(ActionController::Parameters)
      reflection = params[:reflection]
      snapshot = record.source_snapshots.find_by!(revision: record.submitted_revision)
      ReviewWorkflow.validate!(entries, reflection, @content, snapshot)
      review ||= record.build_session_review(source_snapshot: snapshot, content_version: @content.fetch("version"))
      review.update!(entries: entries, reflection: reflection)
    end
    render json: ReviewWorkflow.present(record, @content)
  end

  private

  def require_submission
    owner_session.expire!
    unless owner_session.status == "submitted"
      return render json: { error: "Submit your work before opening the review" }, status: :conflict
    end
    @content = PracticeContent.for(owner_session.exercise_version)
    render json: { error: "Review content is not available for this exercise version" }, status: :unprocessable_content unless @content
  end
end
