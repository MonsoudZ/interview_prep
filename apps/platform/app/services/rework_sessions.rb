class ReworkSessions
  def self.start!(account:, source:, request_id:, mode:, goal:, expected_revision:)
    raise ActiveRecord::RecordNotFound unless source.account_id == account.id
    raise Workspace::Invalid, "Invalid rework request identity" unless request_id.is_a?(String) && request_id.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    raise Workspace::Invalid, "Choose guided or timed practice" unless %w[guided assessment].include?(mode)
    unless goal.is_a?(String) && goal.valid_encoding? && goal.strip.present? && goal.length <= 1500
      raise Workspace::Invalid, "Explain what you intend to improve (maximum 1,500 characters)"
    end
    account.with_lock do
      account.interview_sessions.where(status: "active").where("deadline_at <= ?", Time.current).find_each(&:expire!)
      source.with_lock do
        source.expire_locked!
        raise SessionCommandError, "Submit this attempt before reworking it" unless source.status == "submitted"
        raise SessionCommandError, "The original revision changed. Reload before reworking it." unless expected_revision == source.submitted_revision
        children = account.interview_sessions.where(revision_of_id: source.id)
        existing = children.find_by(rework_request_id: request_id) || children.where.not(status: "submitted").first
        return [existing, false] if existing
        if account.interview_sessions.where.not(status: "submitted").count >= 10
          raise SessionCommandError.new("Resume an existing session before creating another (limit 10).", status: :too_many_requests)
        end
        snapshot = source.source_snapshots.find_by!(revision: source.submitted_revision)
        context = context_for(source, snapshot, goal.strip)
        child = account.interview_sessions.create!(exercise_version: source.exercise_version, mode: mode,
          revision_of: source, rework_request_id: request_id, revision_context: context)
        Workspace.save!(child, snapshot.files.deep_dup)
        [child, true]
      end
    end
  end

  def self.context_for(source, snapshot, goal)
    review = source.session_review
    review = nil unless review&.source_snapshot_id == snapshot.id && review.content_version == PracticeContent.for(source.exercise_version)&.fetch("version")
    run = source.execution_requests.where(source_snapshot_id: snapshot.id, purpose: "tests").order(created_at: :desc, id: :desc).first
    model = source.automated_reviews.where(source_snapshot_id: snapshot.id, status: "completed").order(created_at: :desc, id: :desc).first
    { source_revision: snapshot.revision, captured_at: Time.current.iso8601, goal: goal,
      prior_hints_revealed: source.hint_reveals.count, prior_focus: source.practice_focus,
      self_review: review && { content_version: review.content_version, version: review.lock_version,
        updated_at: review.updated_at.iso8601, entries: review.entries.deep_dup, reflection: review.reflection },
      reported_execution: run && { id: run.id, status: run.status, summary: ExecutionEvidence.summary(run),
        output_truncated: run.result&.fetch("output_truncated", false) || false },
      model_review: model && { model: model.model, model_digest: model.model_digest, prompt_version: model.prompt_version,
        summary: model.report&.fetch("summary", nil), findings: (model.report&.fetch("findings", []) || []).first(8) } }.deep_stringify_keys
  end

  def self.comparison(account, child)
    raise SessionCommandError, "This attempt did not start from a submitted rework" unless child.revision_of_id && child.revision_context
    original = account.interview_sessions.find(child.revision_of_id)
    before = original.source_snapshots.find_by!(revision: child.revision_context.fetch("source_revision"))
    after = child.current_snapshot
    paths = (before.files.keys | after.files.keys).sort
    changes = paths.filter_map do |path|
      previous, current = before.files[path], after.files[path]
      next if previous == current
      { path: path, before: previous, after: current,
        kind: previous.nil? ? "added" : current.nil? ? "removed" : "modified" }
    end
    content = PracticeContent.for(child.exercise_version)
    current_review = child.session_review
    current_review = nil unless child.status == "submitted" && current_review&.source_snapshot_id == after.id
    previous_review = child.revision_context["self_review"]
    comparable = previous_review && current_review && previous_review["content_version"] == current_review.content_version && current_review.content_version == content&.fetch("version")
    criteria = (content&.fetch("criteria") || []).map do |criterion|
      { id: criterion.fetch("id"), title: criterion.fetch("title"),
        before: previous_review&.dig("entries", criterion.fetch("id"), "rating") || "not_observed",
        after: current_review&.entries&.dig(criterion.fetch("id"), "rating") || "not_observed" }
    end
    design = child.exercise_version.track == "system_design" && child.exercise_version.version >= 2
    { source_session_id: original.id, source_revision: before.revision, revision: after.revision, submitted: child.status == "submitted",
      goal: child.revision_context.fetch("goal"), changes: changes, unchanged_files: paths.length - changes.length,
      before_design: design && DesignDocument.validate!(before.files.fetch("diagram.json")),
      after_design: design && DesignDocument.validate!(after.files.fetch("diagram.json")),
      review_comparable: comparable || false, criteria: criteria, current_reflection: current_review&.reflection,
      note: "Only saved source is compared. Earlier review ratings were captured when rework began. Changed source and higher self-ratings do not establish correctness or independent interview performance." }
  end
end
