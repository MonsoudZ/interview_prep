class InterviewSessionsController < ApplicationController
  rescue_from SessionCommandError do |error|
    render json: { error: error.message }, status: error.status
  end

  def index
    MockInterview.where(account: current_account).where.not(status: "completed").find_each { |mock| MockInterviewWorkflow.sync!(mock) }
    current_account.interview_sessions.where(status: "active").where("deadline_at <= ?", Time.current).find_each(&:expire!)
    archived = params[:archived] == "true"
    scope = current_account.interview_sessions
    scope = archived ? scope.where.not(archived_at: nil) : scope.where(archived_at: nil)
    sessions = scope.includes(:exercise_version, :mock_interview_stage).order(updated_at: :desc, id: :desc).limit(100)
    render json: { total: scope.count, limit: 100, archived: archived,
      summary: { ongoing: scope.where.not(status: "submitted").count, submitted: scope.where(status: "submitted").count }, sessions: sessions.map { |record|
      { id: record.id, title: record.exercise_version.title, track: record.exercise_version.track,
        mode: record.mode, status: record.status, archived_at: record.archived_at,
        updated_at: record.updated_at, submitted_at: record.submitted_at, revision_of_id: record.revision_of_id, mock_interview_id: record.mock_interview_stage&.mock_interview_id }
    } }
  end

  def archive
    render json: SessionPresenter.call(SessionOrganization.archive_session!(owner_session))
  end

  def restore
    render json: SessionPresenter.call(SessionOrganization.archive_session!(owner_session, restore: true))
  end

  def create
    exercise = ExerciseVersion.find(params.require(:exercise_id))
    record = nil
    current_account.with_lock do
      current_account.interview_sessions.where(status: "active").where("deadline_at <= ?", Time.current).find_each(&:expire!)
      if current_account.interview_sessions.where(status: %w[draft preparing ready active]).count >= 10
        return render json: { error: "Resume an existing session before creating another (limit 10)." }, status: :too_many_requests
      end
      focus = params[:focus]
      focus = focus.to_unsafe_h if focus.is_a?(ActionController::Parameters)
      record = current_account.interview_sessions.create!(exercise_version: exercise, mode: params.require(:mode),
        practice_focus: PracticeFocus.build!(current_account, exercise, focus))
      files = exercise.starter_files.select { |path, _| Workspace.editable?(path, exercise) }
      Workspace.save!(record, files)
    end
    render json: SessionPresenter.call(record), status: :created
  end

  def show
    record = owner_session
    WorkerJobs.expire_leases!(scope: record.execution_requests)
    record.reload.expire!
    render json: SessionPresenter.call(record)
  end

  def practice
    owner_session.expire!
    render json: PracticeContent.present(owner_session)
  end

  def hint
    record = owner_session
    record.with_lock do
      record.expire_locked!
      unless record.mode == "guided" && record.status != "submitted"
        return conflict("Hints are available in guided practice before submission")
      end
      content = PracticeContent.for(record.exercise_version)
      return render json: { error: "No hints are published for this exercise" }, status: :unprocessable_content unless content
      position = record.hint_reveals.count
      return conflict("Hints changed in another tab. Reopen practice support.") unless params[:expected_position] == position
      return conflict("All hints have been revealed") if position >= content.fetch("hints").length
      record.hint_reveals.create!(position: position, content_version: content.fetch("version"))
    end
    render json: PracticeContent.present(record)
  end

  def snapshot
    record = owner_session
    record.expire!
    record.with_lock do
      record.expire_locked!
      return conflict("This submission is read-only") if record.status == "submitted"
      if record.mock_interview_stage && record.status != "active"
        return conflict("Start this interview stage before editing its source")
      end
      return conflict("A newer save exists. Reload before saving.") unless params[:expected_revision] == record.current_revision
      value = params.require(:files)
      raise Workspace::Invalid, "Expected a file map" unless value.is_a?(ActionController::Parameters)
      files = value.to_unsafe_h
      Workspace.save!(record, files)
      record.update!(status: "draft") if %w[preparing ready].include?(record.status)
    end
    render json: SessionPresenter.call(record)
  end

  def prepare
    record = execution.prepare(request_id: params[:client_request_id])
    render json: SessionPresenter.call(record), status: :accepted
  end

  def execute
    record = execution.execute(request_id: params[:client_request_id])
    render json: SessionPresenter.call(record), status: :accepted
  end

  def start
    render json: SessionPresenter.call(SessionLifecycle.new(owner_session).start)
  end

  def submit
    record = SessionLifecycle.new(owner_session).submit(expected_revision: params[:expected_revision])
    render json: SessionPresenter.call(record)
  end

  private

  def conflict(message)
    render json: { error: message }, status: :conflict
  end

  def execution
    SessionExecution.new(account: current_account, session: owner_session)
  end
end
