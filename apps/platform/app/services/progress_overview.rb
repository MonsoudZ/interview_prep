class ProgressOverview
  GAPS = %w[needs_development approaching_target].freeze
  OBSERVED = (ReviewWorkflow::RATINGS - ["not_observed"]).freeze

  def self.call(account)
    new(account).call
  end

  def initialize(account)
    @account_id = account.id
    @sessions = account.interview_sessions.includes(:exercise_version, :session_review, :hint_reveals, :mock_interview_stage)
      .order(:submitted_at, :created_at, :id).to_a
    @catalog = ExerciseVersion.all.group_by(&:slug).transform_values { |versions| versions.max_by(&:version) }
    @content = {}
    @snapshot_identities = SourceSnapshot.where(id: @sessions.filter_map { |session| session.session_review&.source_snapshot_id })
      .pluck(:id, :interview_session_id, :revision).to_h { |id, session_id, revision| [id, [session_id, revision]] }
  end

  def content(exercise)
    @content[exercise.id] ||= PracticeContent.for(exercise)
  end

  def call
    submitted = @sessions.select { |session| session.status == "submitted" }.reverse
    groups = {}
    attempts = submitted.map do |session|
      rubric = content(session.exercise_version)
      review = session.session_review
      # A mismatched historical rubric/snapshot cannot contribute ratings to progress.
      entries = if rubric && review && review.content_version == rubric.fetch("version") && @snapshot_identities[review.source_snapshot_id] == [session.id, session.submitted_revision]
        review.entries
      else
        {}
      end
      criteria = rubric&.fetch("criteria") || []
      observed = criteria.count { |criterion| OBSERVED.include?(entries.dig(criterion.fetch("id"), "rating")) }
      ((session.revision_of_id || session.mock_interview_stage) ? [] : criteria).each do |criterion|
        key = [session.exercise_version.slug, rubric.fetch("version"), criterion.fetch("id")].join(":")
        group = groups[key] ||= { key: key, track: session.exercise_version.track, exercise: session.exercise_version.title,
          exercise_version: session.exercise_version.version, slug: session.exercise_version.slug,
          content_version: rubric.fetch("version"), criterion_id: criterion.fetch("id"), title: criterion.fetch("title"),
          practice: criterion.fetch("practice"), observations: [] }
        entry = entries[criterion.fetch("id")]
        if entry && OBSERVED.include?(entry["rating"])
          group[:observations] << { session_id: session.id, submitted_at: session.submitted_at, mode: session.mode,
            rating: entry["rating"], notes: entry["notes"], hints_revealed: session.hint_reveals.length }
        end
      end
      { id: session.id, title: session.exercise_version.title, track: session.exercise_version.track,
        exercise_version: session.exercise_version.version, mode: session.mode, submitted_at: session.submitted_at,
        observed: observed, total: criteria.length, review_updated_at: review&.updated_at,
        reflection: review&.reflection.to_s, hints_revealed: session.hint_reveals.length, practice_focus: session.practice_focus,
        revision_of_id: session.revision_of_id, mock_interview_id: session.mock_interview_stage&.mock_interview_id }
    end
    skills = groups.values.filter_map do |group|
      observations = group[:observations] # Newest submission first; editing an old review does not reorder attempts.
      next if observations.empty?
      latest = observations.first
      previous = observations.second
      gap_count = observations.count { |item| GAPS.include?(item[:rating]) }
      trend = if previous
        delta = OBSERVED.index(latest[:rating]) <=> OBSERVED.index(previous[:rating])
        { -1 => "lower", 0 => "unchanged", 1 => "higher" }.fetch(delta)
      else
        "first_observation"
      end
      target = @catalog[group[:slug]]
      focused = @sessions.reverse.find { |candidate| candidate.practice_focus&.values_at("source_session_id", "criterion_id", "content_version") == [latest[:session_id], group[:criterion_id], group[:content_version]] }
      newer = submitted.find { |candidate| candidate.revision_of_id.nil? && candidate.mock_interview_stage.nil? && candidate.exercise_version.slug == group[:slug] && content(candidate.exercise_version)&.fetch("version") == group[:content_version] }
      group.merge(open_gap: GAPS.include?(latest[:rating]), recurring: GAPS.include?(latest[:rating]) && gap_count >= 2,
        gap_count: gap_count, observation_count: observations.length, trend: trend, latest: latest,
        observations: observations.first(8), history_truncated: observations.length > 8,
        exercise_id: target&.id, target_version: target&.version,
        next_session_id: focused&.id || (newer&.id if newer&.id != latest[:session_id]),
        next_session_status: focused&.status || (newer&.status if newer&.id != latest[:session_id]))
    end
    skills.each do |item|
      latest_content = content(@catalog.fetch(item[:slug]))&.fetch("version")
      item[:historical] = item[:content_version] != latest_content && skills.any? { |other| other[:slug] == item[:slug] && other[:content_version] == latest_content }
    end
    gaps = skills.select { |item| item[:open_gap] && !item[:historical] }.sort_by do |item|
      [item[:recurring] ? 0 : 1, -item[:gap_count], OBSERVED.index(item[:latest][:rating]), -item[:latest][:submitted_at].to_i, item[:key]]
    end
    recent = attempts.first(20)
    runs = ExecutionRequest.joins(:source_snapshot, :interview_session).where(interview_session_id: recent.map { |attempt| attempt[:id] }, purpose: "tests")
      .where("source_snapshots.revision = interview_sessions.submitted_revision").order(created_at: :desc, id: :desc).to_a.group_by(&:interview_session_id)
    recent.each do |attempt|
      run = runs[attempt[:id]]&.first
      attempt[:execution] = run && { id: run.id, status: run.status, summary: ExecutionEvidence.summary(run),
        output_truncated: run.result&.fetch("output_truncated", false) || false }
    end
    { summary: { submitted: submitted.length, self_reviews_started: attempts.count { |attempt| attempt[:observed] > 0 },
        awaiting_review: attempts.count { |attempt| attempt[:total] > attempt[:observed] }, open_gaps: gaps.length,
        recurring_gaps: gaps.count { |item| item[:recurring] } },
      plan: gaps, skills: skills.sort_by { |item| [item[:track], item[:exercise], item[:title]] },
      awaiting_review: attempts.select { |attempt| attempt[:total] > attempt[:observed] },
      recent_attempts: recent, recent_limit: 20, followups: FollowupWorkflow.recent_for(@account_id),
      method: "Self-assessments only. One observation per criterion per submission; revisions of a saved review replace that observation. Comparisons stay within the same exercise and rubric version. Once you assess a current rubric, older rubrics remain in history and leave the active plan without being marked resolved. Reworks and mock interview stages appear in history and the review queue, but do not change starter-attempt trends or close their gaps. Tests and model feedback do not determine these ratings." }
  end
end
