class FollowupsController < ApplicationController
  rescue_from SessionCommandError do |error|
    render json: { error: error.message }, status: error.status
  end

  def index
    source = owner_session
    source.expire!
    raise SessionCommandError, "Submit your work before opening follow-ups" unless source.status == "submitted"
    scope = source.followup_rounds
    FollowupWorkflow.expire_scope!(scope)
    content = PracticeContent.for(source.exercise_version)
    raise Workspace::Invalid, "No follow-up questions are published for this version" unless content
    question_count = content.fetch("criteria").length + 1
    render json: { active: scope.where(status: %w[ready active]).first&.as_json(only: [:id, :mode, :status]),
      question_count: question_count, duration_seconds: question_count * 120,
      completed: scope.where(status: "completed").order(completed_at: :desc).limit(5).as_json(only: [:id, :mode, :completed_at]) }
  end

  def create
    round, created = FollowupWorkflow.create!(current_account, owner_session, params[:client_request_id], params[:mode])
    render json: FollowupWorkflow.present(round).merge(reused: !created), status: created ? :created : :ok
  end

  def show
    render json: FollowupWorkflow.present(owner_round)
  end

  def update
    round = owner_round
    FollowupWorkflow.command!(round, params)
    render json: FollowupWorkflow.present(round)
  end

  private
  def owner_round
    @round ||= FollowupRound.joins(:interview_session).where(interview_sessions: { account_id: current_account.id }).find(params[:id])
  end
end
