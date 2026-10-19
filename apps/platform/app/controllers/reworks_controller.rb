class ReworksController < ApplicationController
  rescue_from SessionCommandError do |error|
    render json: { error: error.message }, status: error.status
  end

  def show
    source = owner_session
    source.expire!
    raise SessionCommandError, "Submit this attempt before reworking it" unless source.status == "submitted"
    children = current_account.interview_sessions.where(revision_of_id: source.id)
    children.where(status: "active").where("deadline_at <= ?", Time.current).find_each(&:expire!)
    render json: { active: children.where.not(status: "submitted").first&.as_json(only: [:id, :mode, :status]),
      submitted: children.where(status: "submitted").order(submitted_at: :desc).limit(5).as_json(only: [:id, :mode, :submitted_at]),
      source_session_id: source.id, source_revision: source.submitted_revision }
  end

  def create
    record, created = ReworkSessions.start!(account: current_account, source: owner_session,
      request_id: params[:client_request_id], mode: params[:mode], goal: params[:goal], expected_revision: params[:expected_revision])
    render json: SessionPresenter.call(record).merge(rework_reused: !created), status: created ? :created : :ok
  end

  def comparison
    child = owner_session
    child.expire!
    render json: ReworkSessions.comparison(current_account, child)
  end
end
