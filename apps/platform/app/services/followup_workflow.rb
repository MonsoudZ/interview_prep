class FollowupWorkflow
  SELF_RATINGS = %w[not_observed needs_practice explained].freeze

  def self.create!(account, session, request_id, mode)
    raise ActiveRecord::RecordNotFound unless session.account_id == account.id
    raise SessionCommandError, "Restore this session before starting a new follow-up round" if session.archived_at
    unless request_id.is_a?(String) && request_id.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
      raise Workspace::Invalid, "Invalid follow-up request identity"
    end
    raise Workspace::Invalid, "Choose guided or timed follow-up" unless %w[guided assessment].include?(mode)
    if session.mock_interview_stage && session.mock_interview_stage.mock_interview.status != "completed"
      raise SessionCommandError, "Use the mock interview to open its cross-exercise follow-up stage"
    end
    account.with_lock do
      session.with_lock do
        raise SessionCommandError, "Restore this session before starting a new follow-up round" if session.archived_at
        session.expire_locked!
        raise SessionCommandError, "Submit your work before opening a follow-up round" unless session.status == "submitted"
        expire_scope!(FollowupRound.joins(:interview_session).where(interview_sessions: { account_id: account.id }))
        existing = session.followup_rounds.find_by(client_request_id: request_id) || session.followup_rounds.where(status: %w[ready active]).first
        return [existing, false] if existing
        if FollowupRound.joins(:interview_session).where(interview_sessions: { account_id: account.id }, status: %w[ready active]).count >= 2
          raise SessionCommandError.new("Two follow-up rounds are unfinished. Resume one before creating another.", status: :too_many_requests)
        end
        content = PracticeContent.for(session.exercise_version)
        raise Workspace::Invalid, "No follow-up questions are published for this version" unless content
        questions = content.fetch("criteria").map do |criterion|
          { "id" => criterion.fetch("id"), "title" => criterion.fetch("title"), "kind" => "criterion",
            "prompt" => criterion.fetch("probe"), "target" => criterion.fetch("target"), "practice" => criterion.fetch("practice") }
        end
        behavioral = session.exercise_version.track == "behavioral"
        questions << { "id" => "extension", "title" => behavioral ? "Reflection and transfer" : "Changed requirement", "kind" => "extension", "prompt" => content.fetch("follow_up"),
          "target" => behavioral ? "Explain how you would adapt your actions without inventing outcomes or treating hindsight as knowledge you had at the time." : "State the changed assumptions, required guarantees, failure cases, and tradeoffs. Treat this as an extension, not a missing original requirement.",
          "practice" => behavioral ? "Describe one different constraint and the specific behavior you would change." : "Explain how the extension changes the original solution, then test your reasoning with one counterexample." }
        round = session.followup_rounds.create!(source_snapshot: session.source_snapshots.find_by!(revision: session.submitted_revision),
          client_request_id: request_id, mode: mode, content_version: content.fetch("version"), questions: questions,
          duration_seconds: questions.length * 120)
        [round, true]
      end
    end
  end

  def self.expire_scope!(scope)
    scope.where(status: "active").where("followup_rounds.deadline_at <= ?", Time.current).find_each do |round|
      round.with_lock { round.expire_locked! }
    end
  end

  def self.recent_for(account_id)
    FollowupRound.joins(:interview_session).where(interview_sessions: { account_id: account_id, archived_at: nil })
      .includes(interview_session: :exercise_version).order(updated_at: :desc, id: :desc).limit(10).map do |round|
        session = round.interview_session
        { id: round.id, session_id: session.id, track: session.exercise_version.track, title: session.exercise_version.title,
          status: round.status, mode: round.mode, completed_at: round.completed_at, question_count: round.questions.length,
          answered: round.answers.values.count { |answer| answer["status"] == "answered" },
          self_reported_gaps: round.review_entries.values.count { |entry| entry["rating"] == "needs_practice" } }
      end
  end

  def self.command!(round, params)
    failure = nil
    round.with_lock do
      round.expire_locked!
      begin
        unless params[:expected_version].is_a?(Integer) && params[:expected_version] == round.lock_version
          raise SessionCommandError, "This round changed in another tab. Your local text is preserved; reload the saved round before continuing."
        end
        command = params[:command]
        if command == "start"
          raise SessionCommandError, "This round has already started" unless round.status == "ready"
          mode = params[:mode] || round.mode
          raise Workspace::Invalid, "Choose guided or timed follow-up" unless %w[guided assessment].include?(mode)
          stage = round.mock_interview_stage
          if stage
            raise SessionCommandError, "Mock interview follow-ups are timed" unless mode == "assessment"
            parent = stage.mock_interview
            raise SessionCommandError, "This interview stage is no longer current" unless parent.status == "active" && parent.stage_index == stage.position
          end
          deadline = mode == "assessment" ? round.duration_seconds.seconds.from_now : nil
          deadline = [deadline, stage.mock_interview.deadline_at].compact.min if stage
          round.update!(mode: mode, status: "active", started_at: Time.current, deadline_at: deadline)
        elsif command == "review"
          review!(round, params)
        else
          raise SessionCommandError, "This round is no longer accepting answers" unless round.status == "active"
          raise SessionCommandError, "The question changed. Reload before continuing." unless params[:question_index].is_a?(Integer) && params[:question_index] == round.question_index
          text = params[:answer]
          raise Workspace::Invalid, "Answers must be text, at most 8,000 characters" unless text.is_a?(String) && text.valid_encoding? && text.length <= 8000
          case command
          when "save"
            round.update!(current_draft: text)
          when "next", "skip"
            raise Workspace::Invalid, "Write an answer or explicitly skip this question" if command == "next" && text.strip.empty?
            question = round.questions.fetch(round.question_index)
            answers = round.answers.merge(question.fetch("id") => { "text" => text,
              "status" => command == "skip" ? "skipped" : "answered", "saved_at" => Time.current.iso8601 })
            round.update!(answers: answers, current_draft: "", question_index: round.question_index + 1)
            round.complete_locked!("all_questions") if round.question_index == round.questions.length
          when "finish"
            round.update!(current_draft: text)
            round.complete_locked!("finished_early")
          else
            raise Workspace::Invalid, "Unknown follow-up command"
          end
        end
      rescue SessionCommandError, Workspace::Invalid => error
        # Keep deadline completion committed even when a late/stale write is rejected.
        failure = error
      end
    end
    raise failure if failure
    round
  end

  def self.review!(round, params)
    raise SessionCommandError, "Finish the round before reviewing it" unless round.status == "completed"
    entries = params[:review_entries]
    entries = entries.to_unsafe_h if entries.is_a?(ActionController::Parameters)
    reflection = params[:reflection]
    unless entries.is_a?(Hash) && (entries.keys - round.questions.map { |q| q.fetch("id") }).empty? && reflection.is_a?(String) && reflection.length <= 4000
      raise Workspace::Invalid, "Invalid follow-up review (reflection maximum 4,000 characters)"
    end
    entries.each do |id, entry|
      unless entry.is_a?(Hash) && entry.keys.sort == %w[note rating] && SELF_RATINGS.include?(entry["rating"]) && entry["note"].is_a?(String) && entry["note"].length <= 2000
        raise Workspace::Invalid, "Invalid self-check (note maximum 2,000 characters)"
      end
      if entry["rating"] != "not_observed" && entry["note"].strip.empty?
        raise Workspace::Invalid, "Explain the reason for each observed self-check"
      end
      if entry["rating"] == "explained" && (round.answers.dig(id, "status") != "answered" || round.answers.dig(id, "text").to_s.strip.empty?)
        raise Workspace::Invalid, "A skipped, partial, or unanswered question cannot be marked explained"
      end
    end
    round.update!(review_entries: entries, reflection: reflection)
  end

  def self.present(round)
    round.with_lock { round.expire_locked! }
    session = round.interview_session
    question = round.questions[round.question_index] if round.status == "active"
    stage = round.mock_interview_stage
    { id: round.id, session_id: session.id, title: stage ? stage.mock_interview.title : session.exercise_version.title, source_revision: round.source_snapshot.revision,
      content_version: round.content_version, mode: round.mode, status: round.status, version: round.lock_version,
      question_index: round.question_index, question_count: round.questions.length,
      question: question && question.slice("id", "title", "kind", "prompt"),
      current_draft: round.status == "active" ? round.current_draft : "", duration_seconds: round.duration_seconds,
      started_at: round.started_at, deadline_at: round.deadline_at, completed_at: round.completed_at,
      completion_reason: round.completion_reason, server_time: Time.current,
      transcript: round.status == "completed" ? round.questions.map { |item| item.merge("answer" => round.answers[item.fetch("id")] || { "text" => "", "status" => "unanswered" }) } : nil,
      review_entries: round.status == "completed" ? round.review_entries : nil, reflection: round.status == "completed" ? round.reflection : nil,
      mock_interview_id: stage&.mock_interview_id,
      source_submissions: stage ? round.questions.map { |item| item.slice("source_session_id", "source_revision") }.uniq : nil,
      prior_exposure: true, source_is_rework: session.revision_of_id.present? }
  end
end
