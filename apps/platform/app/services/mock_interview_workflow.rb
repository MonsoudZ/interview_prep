# Published schedules are captured as stage rows; later catalog edits cannot change a booked loop.
class MockInterviewWorkflow
  PLANS = {
    "senior-backend" => { title: "Senior backend interview", stages: [["invoice-amendments", 1, 60], ["merge-intervals", 2, 35], ["webhook-delivery", 2, 40], [nil, nil, 14]] },
    "debugging" => { title: "Debugging and architecture", stages: [["support-escalations", 1, 40], ["webhook-delivery", 2, 35], [nil, nil, 14]] },
    "migration" => { title: "Data migration and architecture", stages: [["safe-backfill", 1, 60], ["webhook-delivery", 2, 40], [nil, nil, 14]] }
  }.freeze

  def self.plans
    PLANS.map do |key, plan|
      { key: key, title: plan[:title], duration_minutes: plan[:stages].sum { |item| item[2] }, stages: plan[:stages].map do |slug, version, minutes|
        { title: slug ? ExerciseVersion.find_by!(slug: slug, version: version).title : "Cross-exercise follow-ups", duration_minutes: minutes }
      end }
    end
  end

  def self.create!(account, key, request_id)
    raise Workspace::Invalid, "Unknown interview plan" unless PLANS.key?(key)
    raise Workspace::Invalid, "Invalid interview request identity" unless request_id.is_a?(String) && request_id.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    account.with_lock do
      existing = MockInterview.find_by(account: account, client_request_id: request_id)
      if existing
        raise SessionCommandError, "Request identity belongs to another interview plan" unless existing.plan_key == key
        return existing
      end
      MockInterview.where(account: account).where.not(status: "completed").find_each { |item| sync!(item) }
      if MockInterview.where(account: account).where.not(status: "completed").count >= 2
        raise SessionCommandError.new("Finish an existing mock interview first (limit two).", status: :too_many_requests)
      end
      account.interview_sessions.where(status: "active").where("deadline_at <= ?", Time.current).find_each(&:expire!)
      unfinished = account.interview_sessions.where(status: %w[draft preparing ready active]).count
      raise SessionCommandError.new("Resume an existing session first (limit ten).", status: :too_many_requests) if unfinished >= 10
      plan = PLANS.fetch(key)
      mock = MockInterview.create!(account: account, plan_key: key, title: plan[:title], client_request_id: request_id)
      plan[:stages].each_with_index do |(slug, version, minutes), position|
        exercise = slug ? ExerciseVersion.find_by!(slug: slug, version: version) : nil
        mock.mock_interview_stages.create!(position: position, exercise_version: exercise,
          kind: slug ? "workspace" : "followup", title: exercise&.title || "Cross-exercise follow-ups", duration_seconds: minutes * 60)
      end
      provision!(mock, mock.mock_interview_stages.first)
      mock
    end
  end

  def self.current!(mock, stage)
    unless mock.status != "completed" && stage.position == mock.stage_index
      raise SessionCommandError, "Return to the mock interview to continue its current stage"
    end
  end

  # Parent lock always precedes the child lock. Start only after environment readiness checks.
  def self.start_session!(session)
    stage = MockInterviewStage.find_by(interview_session: session)
    return yield(nil) unless stage
    mock = stage.mock_interview
    result = nil
    failure = nil
    mock.with_lock do
      sync_locked!(mock)
      begin
        current!(mock, stage)
        result = yield(deadline_for(mock, stage))
        start_clock!(mock) unless mock.started_at
      rescue SessionCommandError, Workspace::Invalid => error
        failure = error
      end
    end
    raise failure if failure
    result
  end

  def self.start_clock!(mock)
    mock.update!(status: "active", started_at: Time.current,
      deadline_at: mock.mock_interview_stages.sum(:duration_seconds).seconds.from_now)
  end

  def self.deadline_for(mock, stage)
    [Time.current + stage.duration_seconds, mock.deadline_at].compact.min
  end

  def self.command!(mock, params)
    failure = nil
    mock.with_lock do
      sync_locked!(mock)
      begin
        raise SessionCommandError, "Interview changed. Reload before continuing." unless params[:expected_version].is_a?(Integer) && params[:expected_version] == mock.lock_version
        case params[:command]
        when "advance"
          raise SessionCommandError, "This interview is completed" if mock.status == "completed"
          stage = mock.mock_interview_stages.find_by!(position: mock.stage_index)
          raise SessionCommandError, "Submit or finish the current stage before continuing" unless finished?(stage)
          next_stage = mock.mock_interview_stages.find_by(position: mock.stage_index + 1)
          if next_stage
            provision!(mock, next_stage)
            mock.update!(stage_index: next_stage.position)
          else
            complete_locked!(mock, "all_stages")
          end
        when "finish"
          raise SessionCommandError, "This interview is completed" if mock.status == "completed"
          complete_locked!(mock, "finished_early")
        when "reflect"
          raise SessionCommandError, "Finish the interview before writing the overall reflection" unless mock.status == "completed"
          text = params[:reflection]
          raise Workspace::Invalid, "Reflection must be text, maximum 4,000 characters" unless text.is_a?(String) && text.length <= 4000
          mock.update!(reflection: text)
        else
          raise Workspace::Invalid, "Unknown interview command"
        end
      rescue SessionCommandError, Workspace::Invalid => error
        failure = error
      end
    end
    raise failure if failure
    mock
  end

  def self.sync!(mock)
    mock.with_lock { sync_locked!(mock) }
    mock
  end

  def self.sync_locked!(mock)
    return if mock.status == "completed"
    mock.mock_interview_stages.each do |stage|
      stage.interview_session&.expire!
      stage.followup_round&.with_lock { stage.followup_round.expire_locked! }
    end
    complete_locked!(mock, "deadline") if mock.deadline_at && mock.deadline_at <= Time.current
  end

  def self.complete_locked!(mock, reason)
    mock.mock_interview_stages.each do |stage|
      if (session = stage.interview_session)
        session.with_lock do
          session.expire_locked!
          unless session.status == "submitted"
            session.update!(status: "submitted", submitted_revision: session.current_revision,
              submitted_at: reason == "deadline" ? mock.deadline_at : Time.current)
          end
        end
      end
      if (round = stage.followup_round)
        round.with_lock do
          round.expire_locked!
          round.complete_locked!(reason == "deadline" ? "interview_deadline" : "interview_finished") unless round.status == "completed"
        end
      end
    end
    mock.update!(status: "completed", completion_reason: reason,
      completed_at: reason == "deadline" ? mock.deadline_at : Time.current)
  end

  def self.finished?(stage)
    stage.interview_session&.status == "submitted" || stage.followup_round&.status == "completed"
  end

  def self.provision!(mock, stage)
    return if stage.interview_session_id || stage.followup_round_id
    if stage.kind == "workspace"
      if mock.account.interview_sessions.where(status: %w[draft preparing ready active]).count >= 10
        raise SessionCommandError.new("Resume an existing session first (limit ten).", status: :too_many_requests)
      end
      session = mock.account.interview_sessions.create!(exercise_version: stage.exercise_version, mode: "assessment")
      Workspace.save!(session, stage.exercise_version.starter_files.select { |path, _| Workspace.editable?(path, stage.exercise_version) })
      stage.update!(interview_session: session)
    else
      sources = mock.mock_interview_stages.where(kind: "workspace").includes(interview_session: :exercise_version).map(&:interview_session)
      raise SessionCommandError, "Submit every workspace before the follow-up round" unless sources.all? { |source| source&.status == "submitted" }
      quota = FollowupRound.joins(:interview_session).where(interview_sessions: { account_id: mock.account_id })
      FollowupWorkflow.expire_scope!(quota)
      raise SessionCommandError.new("Finish an existing follow-up round first (limit two).", status: :too_many_requests) if quota.where(status: %w[ready active]).count >= 2
      per_source = sources.length == 3 ? 2 : 3
      questions = sources.each_with_index.flat_map do |source, index|
        PracticeContent.for(source.exercise_version).fetch("criteria").first(per_source).map do |criterion|
          criterion.slice("title", "target", "practice").merge("id" => "#{index}-#{criterion.fetch('id')}", "kind" => "criterion",
            "prompt" => "#{source.exercise_version.title}: #{criterion.fetch('probe')}",
            "source_session_id" => source.id, "source_revision" => source.submitted_revision)
        end
      end
      design = sources.last
      content = PracticeContent.for(design.exercise_version)
      questions << { "id" => "extension", "title" => "Changed requirement", "kind" => "extension", "prompt" => content.fetch("follow_up"),
        "target" => "State the changed assumptions, guarantees and tradeoffs; this is an extension of the original task.",
        "practice" => "Revisit the design with one failure scenario.", "source_session_id" => design.id, "source_revision" => design.submitted_revision }
      round = design.followup_rounds.create!(client_request_id: stage.id, mode: "assessment", content_version: "mock-followups-v1",
        source_snapshot: design.source_snapshots.find_by!(revision: design.submitted_revision), questions: questions, duration_seconds: stage.duration_seconds)
      stage.update!(followup_round: round)
    end
  end

  def self.present(mock)
    sync!(mock)
    stages = mock.mock_interview_stages.includes(:exercise_version, :interview_session, :followup_round).map do |stage|
      session, round = stage.interview_session, stage.followup_round
      stage_status = if finished?(stage)
        (session && !session.started_at) || (round && !round.started_at) ? "unattempted" : "completed"
      elsif mock.status == "completed"
        "unattempted"
      elsif stage.position == mock.stage_index
        "current"
      else
        "pending"
      end
      evidence = nil
      if mock.status == "completed" && session&.submitted_revision
        snapshot = session.source_snapshots.find_by!(revision: session.submitted_revision)
        runs = session.execution_requests.where(source_snapshot: snapshot, purpose: "tests").order(created_at: :desc)
        review = session.session_review
        rubric = PracticeContent.for(session.exercise_version)
        review = nil unless review && review.source_snapshot_id == snapshot.id && review.content_version == rubric&.fetch("version")
        evidence = { track: session.exercise_version.track, revision: snapshot.revision, submitted_at: session.submitted_at, started_at: session.started_at,
          reported_tests: runs.limit(5).map { |run| { id: run.id, status: run.status, summary: ExecutionEvidence.summary(run) } },
          self_assessment: review&.entries || {}, criteria: rubric&.fetch("criteria"),
          assistance_count: session.hint_reveals.count,
          model_reviews: session.automated_reviews.where(status: "completed", source_snapshot: snapshot).map { |item| { id: item.id, status: item.status } } }
      end
      { position: stage.position, kind: stage.kind, title: stage.title, duration_seconds: stage.duration_seconds, status: stage_status,
        session_id: session&.id, session_status: session&.status, source_session_id: round&.interview_session_id,
        followup_id: round&.id, followup_status: round&.status, exercise_version: stage.exercise_version&.version,
        started_at: session&.started_at || round&.started_at, deadline_at: session&.deadline_at || round&.deadline_at,
        evidence: evidence, transcript: mock.status == "completed" && round ? FollowupWorkflow.present(round) : nil }
    end
    next_steps = stages.flat_map do |stage|
      evidence = stage[:evidence]
      if evidence
        (evidence[:criteria] || []).filter_map do |criterion|
          rating = evidence[:self_assessment].dig(criterion.fetch("id"), "rating")
          if %w[needs_development approaching_target].include?(rating)
            { stage_position: stage[:position], title: criterion.fetch("title"), practice: criterion.fetch("practice"), basis: "Self-assessment: #{rating}" }
          end
        end
      elsif stage[:transcript]
        (stage[:transcript][:transcript] || []).filter_map do |question|
          entry = stage[:transcript][:review_entries][question.fetch("id")]
          if entry && entry["rating"] == "needs_practice"
            { stage_position: stage[:position], title: question.fetch("title"), practice: question.fetch("practice"), basis: "Follow-up self-check: needs practice" }
          end
        end
      else
        []
      end
    end
    { next_steps: next_steps, id: mock.id, archived_at: mock.archived_at, title: mock.title, plan_key: mock.plan_key, status: mock.status, stage_index: mock.stage_index,
      version: mock.lock_version, started_at: mock.started_at, deadline_at: mock.deadline_at, completed_at: mock.completed_at,
      completion_reason: mock.completion_reason, reflection: mock.reflection, server_time: Time.current,
      duration_seconds: mock.mock_interview_stages.sum(:duration_seconds), stages: stages,
      review_kind: "evidence_summary", limitations: "Reported tests, self-assessments and advisory model reviews remain separate. No hiring score or calibrated verdict is calculated." }
  end
end
