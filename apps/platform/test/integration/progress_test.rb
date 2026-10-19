require "test_helper"

class ProgressTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
    load Rails.root.join("db/seeds.rb")
    post "/api/register", params: { name: "Progress fixture", email: "progress@example.test", password: "progress-password-123" }, as: :json
    assert_response :ok
    @account = Account.find_by!(email: "progress@example.test")
    @exercise = ExerciseVersion.where(slug: "merge-intervals").order(version: :desc).first!
    @time = 30.days.ago
  end

  def body = response.parsed_body
  def overview
    get "/api/progress"
    assert_response :ok
    body
  end

  def attempt(rating: nil, exercise: @exercise, mode: "guided", account: @account)
    @time += 1.hour
    record = account.interview_sessions.create!(exercise_version: exercise, mode: mode)
    Workspace.save!(record, exercise.starter_files.select { |path, _| Workspace.editable?(path, exercise) })
    record.update!(status: "submitted", submitted_revision: record.current_revision, submitted_at: @time)
    save_rating(record, rating) if rating
    record
  end

  def save_rating(record, rating)
    content = PracticeContent.for(record.exercise_version)
    criterion = content.fetch("criteria").first.fetch("id")
    review = record.reload.session_review || record.build_session_review(source_snapshot: record.current_snapshot, content_version: content.fetch("version"))
    review.update!(entries: { criterion => { "rating" => rating, "notes" => "Synthetic progress fixture, not an evaluation of the user's work.",
      "evidence" => { "path" => record.current_snapshot.files.keys.first, "start_line" => 1, "end_line" => 1 } } })
    record.reload
  end

  test "progress requires login and only includes the signed-in account" do
    other = Account.create!(email: "private@example.test", name: "Other account", password: "private-password-123")
    private_attempt = attempt(rating: "needs_development", account: other)
    result = overview
    assert_equal 0, result.dig("summary", "submitted")
    assert_empty result["plan"]
    refute_includes response.body, private_attempt.id
    delete "/api/logout", as: :json
    get "/api/progress"
    assert_response :unauthorized
  end

  test "recurring gaps count distinct submissions and old review edits do not reorder observations" do
    first = attempt(rating: "needs_development")
    first.hint_reveals.create!(position: 0, content_version: PracticeContent.for(@exercise).fetch("version"))
    second = attempt(rating: "approaching_target", mode: "assessment")
    unobserved = attempt(rating: "not_observed")
    result = overview
    focus = result.fetch("plan").first
    assert_equal 3, result.dig("summary", "submitted")
    assert_equal 2, result.dig("summary", "self_reviews_started")
    assert_equal 3, result.dig("summary", "awaiting_review")
    assert focus["recurring"]
    assert_equal 2, focus["gap_count"]
    assert_equal 2, focus["observation_count"]
    assert_equal "higher", focus["trend"]
    assert_equal second.id, focus.dig("latest", "session_id")
    assert_equal "assessment", focus.dig("latest", "mode")
    assert_equal 0, focus.dig("latest", "hints_revealed")
    assert_equal 1, focus["observations"].second["hints_revealed"]
    assert_equal unobserved.id, focus["next_session_id"]
    save_rating(first, "approaching_target")
    edited = overview.fetch("plan").first
    assert_equal second.id, edited.dig("latest", "session_id")
    assert_equal 2, edited["observation_count"]
    assert_equal "unchanged", edited["trend"]
  end

  test "later target self-rating closes the active gap while unobserved criteria stay pending" do
    attempt(rating: "needs_development")
    attempt(rating: "needs_development")
    latest = attempt(rating: "meets_target")
    result = overview
    assert_empty result["plan"]
    assert_equal 0, result.dig("summary", "recurring_gaps")
    assert_equal 3, result.dig("summary", "awaiting_review")
    skill = result.fetch("skills").first
    assert_equal "higher", skill["trend"]
    assert_equal latest.id, skill.dig("latest", "session_id")
    assert_equal 2, skill["gap_count"]
    refute skill["open_gap"]
  end

  test "rubric versions and mismatched historical review identities never merge" do
    old_exercise = ExerciseVersion.find_by!(slug: "merge-intervals", version: 1)
    attempt(rating: "needs_development", exercise: old_exercise)
    current = attempt(rating: "needs_development")
    result = overview
    assert_equal 2, result["skills"].length
    refute result["plan"].any? { |item| item["recurring"] }
    assert_equal 2, result["skills"].map { |item| item["content_version"] }.uniq.length
    assert_equal 1, result["plan"].length
    assert result["skills"].find { |item| item["exercise_version"] == 1 }["historical"]
    current.session_review.update!(content_version: "unrelated-rubric")
    result = overview
    assert_equal 1, result["skills"].length
    assert_equal 0, result["recent_attempts"].find { |item| item["id"] == current.id }["observed"]
  end

  test "all historical submissions count even beyond the recent attempts window" do
    105.times { attempt(rating: "needs_development") }
    result = overview
    assert_equal 105, result.dig("summary", "submitted")
    assert_equal 105, result["plan"].first["observation_count"]
    assert_equal 105, result["plan"].first["gap_count"]
    assert_equal 8, result["plan"].first["observations"].length
    assert result["plan"].first["history_truncated"]
    assert_equal 20, result["recent_attempts"].length
  end

  test "practice focus is server-derived survives reload and resumes before another drill" do
    original = attempt(rating: "needs_development")
    focus = { source_session_id: original.id, criterion_id: "correctness" }
    post "/api/sessions", params: { exercise_id: @exercise.id, mode: "guided", focus: focus }, as: :json
    assert_response :created
    next_id = body.fetch("id")
    assert_equal original.id, body.dig("practice_focus", "source_session_id")
    assert_equal PracticeContent.for(@exercise).fetch("criteria").first.fetch("practice"), body.dig("practice_focus", "practice")
    get "/api/sessions/#{next_id}"
    assert_equal "correctness", body.dig("practice_focus", "criterion_id")
    result = overview
    assert_equal next_id, result["plan"].first["next_session_id"]
    assert_equal "draft", result["plan"].first["next_session_status"]
    post "/api/sessions/#{next_id}/start", as: :json
    assert_response :ok
    post "/api/sessions/#{next_id}/submit", params: { expected_revision: body.fetch("revision") }, as: :json
    assert_response :ok
    result = overview
    assert_equal next_id, result["plan"].first["next_session_id"]
    assert_equal "submitted", result["plan"].first["next_session_status"]
    assert_equal 1, result["plan"].first["observation_count"]
  end

  test "practice focus cannot use another account unrelated exercise arbitrary text or a resolved gap" do
    source = attempt(rating: "needs_development")
    focus = { source_session_id: source.id, criterion_id: "correctness" }
    other = Account.create!(email: "isolated@example.test", name: "Other", password: "isolated-password-123")
    private_source = attempt(rating: "needs_development", account: other)
    post "/api/sessions", params: { exercise_id: @exercise.id, mode: "guided", focus: focus.merge(source_session_id: private_source.id) }, as: :json
    assert_response :not_found
    unrelated = ExerciseVersion.find_by!(slug: "webhook-delivery", version: 2)
    post "/api/sessions", params: { exercise_id: unrelated.id, mode: "guided", focus: focus }, as: :json
    assert_response :unprocessable_content
    [focus.merge(practice: "client-supplied"), focus.merge(criterion_id: {}), focus.merge(source_session_id: []), "not a focus"].each do |invalid|
      post "/api/sessions", params: { exercise_id: @exercise.id, mode: "guided", focus: invalid }, as: :json
      assert_response :unprocessable_content
    end
    save_rating(source, "meets_target")
    post "/api/sessions", params: { exercise_id: @exercise.id, mode: "guided", focus: focus }, as: :json
    assert_response :unprocessable_content
    save_rating(source, "needs_development")
    attempt(rating: "meets_target")
    post "/api/sessions", params: { exercise_id: @exercise.id, mode: "guided", focus: focus }, as: :json
    assert_response :unprocessable_content
  end

  test "runner evidence stays revision bound and model feedback cannot change self-rating progress" do
    record = attempt(rating: "needs_development")
    snapshot = record.current_snapshot
    prior = record.source_snapshots.create!(revision: "f" * 64, files: { "solution.rb" => "# different revision\n" })
    [ [prior, "tests"], [snapshot, "prepare"], [snapshot, "tests"] ].each do |source, purpose|
      record.execution_requests.create!(source_snapshot: source, client_request_id: SecureRandom.uuid, purpose: purpose,
        status: "execution_completed", result: { "output" => "12 runs, 30 assertions, 0 failures, 0 errors, 0 skips\n" })
    end
    correct = record.execution_requests.find_by!(source_snapshot: snapshot, purpose: "tests")
    # A clearly synthetic model report must have no effect on the self-assessment plan.
    record.automated_reviews.create!(source_snapshot: snapshot, client_request_id: SecureRandom.uuid,
      status: "completed", prompt_version: "transport-fixture", content_version: "transport-fixture", input: {}, report: { "summary" => "Synthetic model fixture", "criteria" => [{ "id" => "correctness", "rating" => "exceeds_target" }] })
    result = overview
    assert_equal "needs_development", result["plan"].first.dig("latest", "rating")
    assert_equal correct.id, result["recent_attempts"].first.dig("execution", "id")
    assert result["recent_attempts"].first.dig("execution", "summary", "reported")
    assert_equal 12, result["recent_attempts"].first.dig("execution", "summary", "passed")
  end

  test "overdue timed attempts enter the review queue with their preserved submission" do
    record = @account.interview_sessions.create!(exercise_version: @exercise, mode: "assessment")
    Workspace.save!(record, @exercise.starter_files.select { |path, _| Workspace.editable?(path, @exercise) })
    record.update!(status: "active", started_at: 2.hours.ago, deadline_at: 1.hour.ago)
    result = overview
    assert_equal 1, result.dig("summary", "submitted")
    assert_equal record.current_revision, record.reload.submitted_revision
    assert_equal record.id, result["awaiting_review"].first["id"]
  end
end
